package protocol

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/version"
)

const (
	MaxLineBytes = 65536

	CmdStart    = "start"
	CmdStatus   = "status"
	CmdStop     = "stop"
	CmdLogout   = "logout"
	CmdShutdown = "shutdown"

	EventReady         = "ready"
	EventStateChanged  = "stateChanged"
	EventAuthRequired  = "authRequired"
	EventListening     = "listening"
	EventError         = "error"
	EventStopped       = "stopped"

	StateStopped       = "stopped"
	StateStarting      = "starting"
	StateNeedsLogin    = "needsLogin"
	StateNeedsApproval = "needsApproval"
	StateRunning       = "running"
	StateDegraded      = "degraded"
	StateStopping      = "stopping"
	StateFailed        = "failed"

	ErrMalformedJSON              = "MALFORMED_JSON"
	ErrMessageTooLong             = "MESSAGE_TOO_LONG"
	ErrUnknownCommand             = "UNKNOWN_COMMAND"
	ErrProtocolVersionUnsupported = "PROTOCOL_VERSION_UNSUPPORTED"
	ErrSessionNonceMismatch       = "SESSION_NONCE_MISMATCH"
	ErrMissingSessionNonce        = "MISSING_SESSION_NONCE"
	ErrInvalidTarget              = "INVALID_TARGET"
	ErrInvalidListenPort          = "INVALID_LISTEN_PORT"
	ErrInvalidStateDir            = "INVALID_STATE_DIR"
	ErrAlreadyStarted             = "ALREADY_STARTED"
	ErrNotStarted                 = "NOT_STARTED"
	ErrStateLocked                = "STATE_LOCKED"
	ErrBackendFailed              = "BACKEND_FAILED"
	ErrListenFailed               = "LISTEN_FAILED"
	ErrLocalTargetUnreachable     = "LOCAL_TARGET_UNREACHABLE"
	ErrLoginTimeout               = "LOGIN_TIMEOUT"
	ErrShutdown                   = "SHUTDOWN"
	ErrParentEOF                  = "PARENT_EOF"
)

var (
	ErrLineTooLong = errors.New("message exceeds max line length")
	ErrNotJSON     = errors.New("line is not JSON")
)

type Message struct {
	ProtocolVersion int    `json:"protocolVersion"`
	SessionNonce    string `json:"sessionNonce,omitempty"`
	RequestID       string `json:"requestId,omitempty"`
	EventID         uint64 `json:"eventId,omitempty"`
	Command         string `json:"command,omitempty"`
	Event           string `json:"event,omitempty"`
	Target          string `json:"target,omitempty"`
	ListenPort      uint16 `json:"listenPort,omitempty"`
	StateDir        string `json:"stateDir,omitempty"`
	Hostname        string `json:"hostname,omitempty"`
	State           string `json:"state,omitempty"`
	AuthURL         string `json:"authUrl,omitempty"`
	TailnetIP       string `json:"tailnetIp,omitempty"`
	NodeID          string `json:"nodeId,omitempty"`
	Port            uint16 `json:"port,omitempty"`
	Listening       bool   `json:"listening,omitempty"`
	Connections     int    `json:"connections,omitempty"`
	ErrorCode       string `json:"errorCode,omitempty"`
	Error           string `json:"error,omitempty"`
	HelperVersion   string `json:"helperVersion,omitempty"`
	Tailscale       string `json:"tailscale,omitempty"`
	Recoverable     bool   `json:"recoverable,omitempty"`
}

func DecodeLine(line []byte) (*Message, error) {
	if len(line) > MaxLineBytes {
		return nil, ErrLineTooLong
	}
	trim := bytes.TrimSpace(line)
	if len(trim) == 0 {
		return nil, ErrNotJSON
	}
	if trim[0] != '{' {
		return nil, ErrNotJSON
	}
	var m Message
	dec := json.NewDecoder(bytes.NewReader(trim))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&m); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrNotJSON, err)
	}
	if dec.More() {
		return nil, ErrNotJSON
	}
	return &m, nil
}

func EncodeLine(m *Message) ([]byte, error) {
	if m.ProtocolVersion == 0 {
		m.ProtocolVersion = version.Protocol
	}
	b, err := json.Marshal(m)
	if err != nil {
		return nil, err
	}
	if len(b)+1 > MaxLineBytes {
		return nil, ErrLineTooLong
	}
	return append(b, '\n'), nil
}

func ValidateCommand(m *Message) (code, detail string) {
	if m.ProtocolVersion != version.Protocol {
		return ErrProtocolVersionUnsupported, fmt.Sprintf("got %d want %d", m.ProtocolVersion, version.Protocol)
	}
	switch m.Command {
	case CmdStart, CmdStatus, CmdStop, CmdLogout, CmdShutdown:
	default:
		return ErrUnknownCommand, m.Command
	}
	if m.RequestID == "" {
		return ErrMalformedJSON, "requestId required"
	}
	if m.Command == CmdStart {
		if err := ValidateTarget(m.Target); err != nil {
			return ErrInvalidTarget, err.Error()
		}
		if m.ListenPort == 0 {
			return ErrInvalidListenPort, "listenPort required"
		}
		if strings.TrimSpace(m.StateDir) == "" {
			return ErrInvalidStateDir, "stateDir required"
		}
	}
	return "", ""
}

func ValidateTarget(target string) error {
	host, port, ok := strings.Cut(target, ":")
	if !ok || host != "127.0.0.1" {
		return fmt.Errorf("target must be 127.0.0.1:<port>")
	}
	if port == "" || strings.ContainsAny(port, "/[]") {
		return fmt.Errorf("invalid port")
	}
	n := 0
	for _, c := range port {
		if c < '0' || c > '9' {
			return fmt.Errorf("invalid port")
		}
		n = n*10 + int(c-'0')
		if n > 65535 {
			return fmt.Errorf("invalid port")
		}
	}
	if n == 0 {
		return fmt.Errorf("invalid port")
	}
	return nil
}

func KnownCommand(cmd string) bool {
	switch cmd {
	case CmdStart, CmdStatus, CmdStop, CmdLogout, CmdShutdown:
		return true
	}
	return false
}
