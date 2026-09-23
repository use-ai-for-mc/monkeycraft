package wsframe

import (
	"crypto/rand"
	"encoding/binary"
	"errors"
	"io"
	"sync"
	"unicode/utf8"
)

type Role int

const (
	RoleClient Role = iota
	RoleServer
)

type Conn struct {
	rw      io.ReadWriter
	role    Role
	limits  Limits
	muW      sync.Mutex
	muR      sync.Mutex
	closed   bool
	sentClose bool
	closeCh  chan struct{}

	fragOp      Opcode
	fragBuf     []byte
	pendingCtrl []Frame
}

func NewConn(rw io.ReadWriter, role Role, limits Limits) *Conn {
	if limits.MaxFrameBytes <= 0 {
		limits.MaxFrameBytes = DefaultMaxFrameBytes
	}
	if limits.MaxMessageBytes <= 0 {
		limits.MaxMessageBytes = DefaultMaxMessageBytes
	}
	return &Conn{
		rw:      rw,
		role:    role,
		limits:  limits,
		closeCh: make(chan struct{}),
	}
}

func (c *Conn) clientMask() bool { return c.role == RoleClient }

func (c *Conn) WriteMessage(op Opcode, payload []byte) error {
	return c.writeFrame(Frame{Fin: true, Opcode: op, Payload: payload})
}

func (c *Conn) WriteFragmented(op Opcode, payload []byte, chunk int) error {
	if !op.IsData() {
		return ErrBadOpcode
	}
	if chunk <= 0 {
		return c.WriteMessage(op, payload)
	}
	if len(payload) == 0 {
		return c.WriteMessage(op, payload)
	}
	off := 0
	first := true
	for off < len(payload) {
		end := off + chunk
		if end > len(payload) {
			end = len(payload)
		}
		f := Frame{
			Fin:     end == len(payload),
			Opcode:  OpcodeContinuation,
			Payload: payload[off:end],
		}
		if first {
			f.Opcode = op
			first = false
		}
		if err := c.writeFrame(f); err != nil {
			return err
		}
		off = end
	}
	return nil
}

func (c *Conn) WritePing(payload []byte) error {
	if len(payload) > maxControlPayload {
		return ErrControlTooLong
	}
	return c.writeFrame(Frame{Fin: true, Opcode: OpcodePing, Payload: payload})
}

func (c *Conn) WritePong(payload []byte) error {
	if len(payload) > maxControlPayload {
		return ErrControlTooLong
	}
	return c.writeFrame(Frame{Fin: true, Opcode: OpcodePong, Payload: payload})
}

func (c *Conn) WriteClose(code int, reason string) error {
	return c.writeFrame(Frame{
		Fin:     true,
		Opcode:  OpcodeClose,
		Payload: EncodeClosePayload(code, reason),
	})
}

func (c *Conn) writeFrame(f Frame) error {
	c.muW.Lock()
	defer c.muW.Unlock()
	if c.closed && f.Opcode != OpcodeClose {
		return ErrClosed
	}
	if f.Opcode == OpcodeClose && c.sentClose {
		return nil
	}
	if f.Opcode == OpcodeClose {
		c.sentClose = true
	}
	if c.clientMask() {
		f.Masked = true
		if _, err := rand.Read(f.MaskKey[:]); err != nil {
			return err
		}
	} else {
		f.Masked = false
	}
	return WriteFrame(c.rw, f)
}

type Message struct {
	Opcode  Opcode
	Payload []byte
}

func (c *Conn) ReadMessage() (Message, error) {
	c.muR.Lock()
	defer c.muR.Unlock()
	for {
		if len(c.pendingCtrl) > 0 {
			f := c.pendingCtrl[0]
			c.pendingCtrl = c.pendingCtrl[1:]
			msg, err := c.handleControl(f)
			if err != nil || msg != nil {
				if msg != nil {
					return *msg, err
				}
				return Message{}, err
			}
			continue
		}
		expectMasked := c.role == RoleServer
		f, err := ReadFrame(c.rw, c.limits, expectMasked)
		if err != nil {
			return Message{}, err
		}
		if f.Opcode.IsControl() {
			msg, err := c.handleControl(f)
			if err != nil || msg != nil {
				if msg != nil {
					return *msg, err
				}
				return Message{}, err
			}
			continue
		}
		if f.Opcode == OpcodeContinuation {
			if c.fragOp == 0 {
				return Message{}, ErrContinuation
			}
			if err := c.appendFrag(f.Payload); err != nil {
				return Message{}, err
			}
			if f.Fin {
				return c.finishFrag()
			}
			continue
		}
		if !f.Opcode.IsData() {
			return Message{}, ErrBadOpcode
		}
		if c.fragOp != 0 {
			return Message{}, fmtWrap(ErrContinuation, "data opcode during fragmented message")
		}
		if !f.Fin {
			c.fragOp = f.Opcode
			if err := c.appendFrag(f.Payload); err != nil {
				return Message{}, err
			}
			continue
		}
		if f.Opcode == OpcodeText && !utf8.Valid(f.Payload) {
			return Message{}, ErrInvalidUTF8
		}
		return Message{Opcode: f.Opcode, Payload: f.Payload}, nil
	}
}

func fmtWrap(err error, msg string) error {
	return errors.New(msg + ": " + err.Error())
}

func (c *Conn) appendFrag(p []byte) error {
	if len(c.fragBuf)+len(p) > c.limits.MaxMessageBytes {
		return ErrMessageTooBig
	}
	c.fragBuf = append(c.fragBuf, p...)
	return nil
}

func (c *Conn) finishFrag() (Message, error) {
	op := c.fragOp
	buf := c.fragBuf
	c.fragOp = 0
	c.fragBuf = nil
	if op == OpcodeText && !utf8.Valid(buf) {
		return Message{}, ErrInvalidUTF8
	}
	return Message{Opcode: op, Payload: buf}, nil
}

func (c *Conn) handleControl(f Frame) (*Message, error) {
	switch f.Opcode {
	case OpcodePing:
		if err := c.WritePong(f.Payload); err != nil {
			return nil, err
		}
		return nil, nil
	case OpcodePong:
		return nil, nil
	case OpcodeClose:
		code, _, err := ParseClosePayload(f.Payload)
		if err != nil {
			_ = c.WriteClose(CloseProtocolError, "")
			c.markClosed()
			return &Message{Opcode: OpcodeClose, Payload: f.Payload}, err
		}
		_ = c.WriteClose(code, "")
		c.markClosed()
		return &Message{Opcode: OpcodeClose, Payload: f.Payload}, ErrClosed
	default:
		return nil, ErrBadOpcode
	}
}

func (c *Conn) markClosed() {
	c.muW.Lock()
	defer c.muW.Unlock()
	if !c.closed {
		c.closed = true
		close(c.closeCh)
	}
}

func (c *Conn) Close() error {
	c.muW.Lock()
	already := c.closed
	c.muW.Unlock()
	if already {
		return nil
	}
	err := c.WriteClose(CloseNormalClosure, "")
	c.markClosed()
	return err
}

func CloseCodeFromPayload(p []byte) uint16 {
	if len(p) < 2 {
		return CloseNoStatusRcvd
	}
	return binary.BigEndian.Uint16(p[:2])
}
