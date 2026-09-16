package backend

import (
	"context"
	"net"
)

type State string

const (
	StateStopped       State = "stopped"
	StateStarting      State = "starting"
	StateNeedsLogin    State = "needsLogin"
	StateNeedsApproval State = "needsApproval"
	StateRunning       State = "running"
	StateDegraded      State = "degraded"
	StateFailed        State = "failed"
)

type StartConfig struct {
	StateDir string
	Hostname string
}

type Status struct {
	State     State
	AuthURL   string
	TailnetIP string
	NodeID    string
}

type Event struct {
	State   State
	AuthURL string
	Status  Status
	Err     error
}

type Backend interface {
	Start(ctx context.Context, cfg StartConfig) error
	Watch(ctx context.Context) (<-chan Event, error)
	Listen(ctx context.Context, port uint16) (net.Listener, error)
	Status(ctx context.Context) (Status, error)
	Logout(ctx context.Context) error
	Close() error
}

type Factory func() Backend
