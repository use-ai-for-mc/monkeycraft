package wsframe

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"unicode/utf8"
)

const (
	OpcodeContinuation Opcode = 0x0
	OpcodeText         Opcode = 0x1
	OpcodeBinary       Opcode = 0x2
	OpcodeClose        Opcode = 0x8
	OpcodePing         Opcode = 0x9
	OpcodePong         Opcode = 0xA
)

const (
	CloseNormalClosure           = 1000
	CloseGoingAway               = 1001
	CloseProtocolError           = 1002
	CloseUnsupportedData         = 1003
	CloseNoStatusRcvd            = 1005
	CloseAbnormalClosure         = 1006
	CloseInvalidFramePayloadData = 1007
	ClosePolicyViolation         = 1008
	CloseMessageTooBig           = 1009
	CloseMandatoryExtension      = 1010
	CloseInternalError           = 1011
)

const (
	DefaultMaxFrameBytes   = 1 << 20
	DefaultMaxMessageBytes = 4 << 20
	maxControlPayload      = 125
)

var (
	ErrProtocol          = errors.New("wsframe: protocol error")
	ErrMessageTooBig     = errors.New("wsframe: message too big")
	ErrInvalidUTF8       = errors.New("wsframe: invalid utf-8")
	ErrClosed            = errors.New("wsframe: closed")
	ErrReservedBits      = errors.New("wsframe: reserved bits set")
	ErrBadOpcode         = errors.New("wsframe: bad opcode")
	ErrControlFragment   = errors.New("wsframe: control frame fragmented")
	ErrControlTooLong    = errors.New("wsframe: control payload too long")
	ErrMaskedServerFrame = errors.New("wsframe: server frame was masked")
	ErrUnmaskedClient    = errors.New("wsframe: client frame was not masked")
	ErrBadCloseCode      = errors.New("wsframe: bad close code")
	ErrContinuation      = errors.New("wsframe: unexpected continuation")
)

type Opcode byte

func (o Opcode) IsControl() bool {
	return o == OpcodeClose || o == OpcodePing || o == OpcodePong
}

func (o Opcode) IsData() bool {
	return o == OpcodeText || o == OpcodeBinary
}

func (o Opcode) String() string {
	switch o {
	case OpcodeContinuation:
		return "continuation"
	case OpcodeText:
		return "text"
	case OpcodeBinary:
		return "binary"
	case OpcodeClose:
		return "close"
	case OpcodePing:
		return "ping"
	case OpcodePong:
		return "pong"
	default:
		return fmt.Sprintf("opcode(%d)", o)
	}
}

type Frame struct {
	Fin     bool
	Opcode  Opcode
	Masked  bool
	MaskKey [4]byte
	Payload []byte
}

type Limits struct {
	MaxFrameBytes   int
	MaxMessageBytes int
}

func DefaultLimits() Limits {
	return Limits{
		MaxFrameBytes:   DefaultMaxFrameBytes,
		MaxMessageBytes: DefaultMaxMessageBytes,
	}
}

func MaskInPlace(key [4]byte, payload []byte) {
	for i := range payload {
		payload[i] ^= key[i&3]
	}
}

func WriteFrame(w io.Writer, f Frame) error {
	if f.Opcode.IsControl() {
		if !f.Fin {
			return ErrControlFragment
		}
		if len(f.Payload) > maxControlPayload {
			return ErrControlTooLong
		}
	}
	var header [14]byte
	b0 := byte(f.Opcode) & 0x0f
	if f.Fin {
		b0 |= 0x80
	}
	header[0] = b0

	n := len(f.Payload)
	ext := 0
	switch {
	case n <= 125:
		header[1] = byte(n)
	case n <= 0xffff:
		header[1] = 126
		binary.BigEndian.PutUint16(header[2:], uint16(n))
		ext = 2
	default:
		header[1] = 127
		binary.BigEndian.PutUint64(header[2:], uint64(n))
		ext = 8
	}
	maskOff := 2 + ext
	if f.Masked {
		header[1] |= 0x80
		copy(header[maskOff:], f.MaskKey[:])
		maskOff += 4
	}
	if n == 0 {
		_, err := w.Write(header[:maskOff])
		return err
	}
	out := make([]byte, maskOff+n)
	copy(out, header[:maskOff])
	copy(out[maskOff:], f.Payload)
	if f.Masked {
		MaskInPlace(f.MaskKey, out[maskOff:])
	}
	_, err := w.Write(out)
	return err
}

func ReadFrame(r io.Reader, limits Limits, expectMasked bool) (Frame, error) {
	if limits.MaxFrameBytes <= 0 {
		limits.MaxFrameBytes = DefaultMaxFrameBytes
	}
	var hdr [2]byte
	if _, err := io.ReadFull(r, hdr[:]); err != nil {
		return Frame{}, err
	}
	fin := hdr[0]&0x80 != 0
	if hdr[0]&0x70 != 0 {
		return Frame{}, ErrReservedBits
	}
	op := Opcode(hdr[0] & 0x0f)
	if !validOpcode(op) {
		return Frame{}, ErrBadOpcode
	}
	masked := hdr[1]&0x80 != 0
	if expectMasked && !masked {
		return Frame{}, ErrUnmaskedClient
	}
	if !expectMasked && masked {
		return Frame{}, ErrMaskedServerFrame
	}
	n7 := int(hdr[1] & 0x7f)
	var n int
	switch n7 {
	case 126:
		var ext [2]byte
		if _, err := io.ReadFull(r, ext[:]); err != nil {
			return Frame{}, err
		}
		n = int(binary.BigEndian.Uint16(ext[:]))
		if n < 126 {
			return Frame{}, fmt.Errorf("%w: non-minimal 16-bit length", ErrProtocol)
		}
	case 127:
		var ext [8]byte
		if _, err := io.ReadFull(r, ext[:]); err != nil {
			return Frame{}, err
		}
		u := binary.BigEndian.Uint64(ext[:])
		if u&0x8000000000000000 != 0 {
			return Frame{}, fmt.Errorf("%w: 63-bit length msb set", ErrProtocol)
		}
		if u < 65536 {
			return Frame{}, fmt.Errorf("%w: non-minimal 64-bit length", ErrProtocol)
		}
		if u > uint64(limits.MaxFrameBytes) {
			return Frame{}, ErrMessageTooBig
		}
		n = int(u)
	default:
		n = n7
	}
	if op.IsControl() {
		if !fin {
			return Frame{}, ErrControlFragment
		}
		if n > maxControlPayload {
			return Frame{}, ErrControlTooLong
		}
	}
	if n > limits.MaxFrameBytes {
		return Frame{}, ErrMessageTooBig
	}
	var mask [4]byte
	if masked {
		if _, err := io.ReadFull(r, mask[:]); err != nil {
			return Frame{}, err
		}
	}
	payload := make([]byte, n)
	if n > 0 {
		if _, err := io.ReadFull(r, payload); err != nil {
			return Frame{}, err
		}
		if masked {
			MaskInPlace(mask, payload)
		}
	}
	return Frame{
		Fin:     fin,
		Opcode:  op,
		Masked:  masked,
		MaskKey: mask,
		Payload: payload,
	}, nil
}

func validOpcode(op Opcode) bool {
	switch op {
	case OpcodeContinuation, OpcodeText, OpcodeBinary, OpcodeClose, OpcodePing, OpcodePong:
		return true
	default:
		return false
	}
}

func ParseClosePayload(p []byte) (code int, reason string, err error) {
	if len(p) == 0 {
		return CloseNoStatusRcvd, "", nil
	}
	if len(p) == 1 {
		return 0, "", ErrProtocol
	}
	code = int(binary.BigEndian.Uint16(p[:2]))
	if !validCloseCode(code) {
		return code, "", ErrBadCloseCode
	}
	reasonBytes := p[2:]
	if !utf8.Valid(reasonBytes) {
		return code, "", ErrInvalidUTF8
	}
	return code, string(reasonBytes), nil
}

func EncodeClosePayload(code int, reason string) []byte {
	buf := make([]byte, 2+len(reason))
	binary.BigEndian.PutUint16(buf, uint16(code))
	copy(buf[2:], reason)
	return buf
}

func validCloseCode(code int) bool {
	switch code {
	case 1000, 1001, 1002, 1003, 1007, 1008, 1009, 1010, 1011:
		return true
	}
	if code >= 3000 && code <= 4999 {
		return true
	}
	return false
}
