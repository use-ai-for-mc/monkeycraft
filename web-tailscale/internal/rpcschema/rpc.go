package rpcschema

import (
	"encoding/json"
	"errors"
	"fmt"
)

const ProtocolVersion = 1

const (
	KindReq = "req"
	KindRes = "res"
	KindEvt = "evt"
	KindBin = "bin"
)

var Methods = map[string]bool{
	"hello":     true,
	"init":      true,
	"login":     true,
	"logout":    true,
	"status":    true,
	"dialTcp":   true,
	"connRead":  true,
	"connWrite": true,
	"connClose": true,
	"wsOpen":    true,
	"wsSend":    true,
	"wsClose":   true,
	"shutdown":  true,
}

var ErrorCodes = map[string]bool{
	"PROTOCOL":       true,
	"UNSUPPORTED":    true,
	"NOT_RUNNING":    true,
	"NEEDS_LOGIN":    true,
	"NEEDS_APPROVAL": true,
	"CANCELLED":      true,
	"TIMEOUT":        true,
	"QUEUE_FULL":     true,
	"CONN_LIMIT":     true,
	"INVALID_TARGET": true,
	"CLOSED":         true,
	"WORKER_CRASH":   true,
	"WASM_LOAD":      true,
	"WSS_BLOCKED":    true,
	"INTERNAL":       true,
}

type ErrorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type Envelope struct {
	ProtocolVersion int             `json:"protocolVersion"`
	Kind            string          `json:"kind"`
	ID              string          `json:"id,omitempty"`
	EventID         int             `json:"eventId,omitempty"`
	Method          string          `json:"method,omitempty"`
	OK              *bool           `json:"ok,omitempty"`
	Error           *ErrorBody      `json:"error,omitempty"`
	Payload         json.RawMessage `json:"payload,omitempty"`
}

type DialTcpPayload struct {
	Host      string `json:"host"`
	Port      int    `json:"port"`
	TimeoutMs int    `json:"timeoutMs,omitempty"`
}

var (
	ErrBadVersion = errors.New("rpcschema: protocolVersion must be 1")
	ErrBadKind    = errors.New("rpcschema: unknown kind")
	ErrBadMethod  = errors.New("rpcschema: unknown method")
	ErrBadID      = errors.New("rpcschema: missing id")
	ErrBadError   = errors.New("rpcschema: invalid error")
	ErrTooLarge   = errors.New("rpcschema: message too large")
	ErrBadDial    = errors.New("rpcschema: invalid dialTcp payload")
)

const MaxJSONBytes = 64 << 10

func Parse(raw []byte) (Envelope, error) {
	if len(raw) > MaxJSONBytes {
		return Envelope{}, ErrTooLarge
	}
	var e Envelope
	if err := json.Unmarshal(raw, &e); err != nil {
		return Envelope{}, err
	}
	if e.ProtocolVersion != ProtocolVersion {
		return Envelope{}, ErrBadVersion
	}
	switch e.Kind {
	case KindReq, KindRes, KindEvt, KindBin:
	default:
		return Envelope{}, ErrBadKind
	}
	if e.Kind == KindReq || e.Kind == KindRes {
		if e.ID == "" {
			return Envelope{}, ErrBadID
		}
	}
	if e.Kind == KindReq {
		if !Methods[e.Method] {
			return Envelope{}, ErrBadMethod
		}
	}
	if e.Error != nil {
		if !ErrorCodes[e.Error.Code] {
			return Envelope{}, ErrBadError
		}
		if len(e.Error.Message) > 200 {
			e.Error.Message = e.Error.Message[:200]
		}
	}
	if e.Kind == KindEvt && e.EventID < 1 {
		return Envelope{}, fmt.Errorf("rpcschema: eventId required")
	}
	return e, nil
}

func ValidateDial(p DialTcpPayload) error {
	if p.Host == "" || len(p.Host) > 253 {
		return ErrBadDial
	}
	if p.Port < 1 || p.Port > 65535 {
		return ErrBadDial
	}
	if p.TimeoutMs < 0 || p.TimeoutMs > 60000 {
		return ErrBadDial
	}
	return nil
}
