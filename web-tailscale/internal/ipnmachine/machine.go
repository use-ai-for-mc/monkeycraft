package ipnmachine

import (
	"errors"
	"sync"
)

type State string

const (
	NoState          State = "NoState"
	InUseOtherUser   State = "InUseOtherUser"
	NeedsLogin       State = "NeedsLogin"
	NeedsMachineAuth State = "NeedsMachineAuth"
	Stopped          State = "Stopped"
	Starting         State = "Starting"
	Running          State = "Running"
)

type ProductState string

const (
	Unavailable   ProductState = "unavailable"
	ProdStopped   ProductState = "stopped"
	ProdStarting  ProductState = "starting"
	ProdNeedsLogin ProductState = "needsLogin"
	ProdNeedsApproval ProductState = "needsApproval"
	ProdRunning   ProductState = "running"
	ProdDegraded  ProductState = "degraded"
	ProdStopping  ProductState = "stopping"
	ProdFailed    ProductState = "failed"
)

type Node struct {
	Name       string   `json:"name"`
	Addresses  []string `json:"addresses"`
	MachineKey string   `json:"machineKey,omitempty"`
	NodeKey    string   `json:"nodeKey,omitempty"`
	NodeID     string   `json:"nodeId,omitempty"`
	StableID   string   `json:"stableId,omitempty"`
	Online     *bool    `json:"online,omitempty"`
}

type NetMap struct {
	Self      Node   `json:"self"`
	Peers     []Node `json:"peers"`
	LockedOut bool   `json:"lockedOut"`
}

type Snapshot struct {
	IPN            State
	Product        ProductState
	HasAuthURL     bool
	AuthURLPending bool
	NetMap         *NetMap
	LoggedOut      bool
}

type Machine struct {
	mu       sync.Mutex
	ipn      State
	product  ProductState
	authURL  bool
	netMap   *NetMap
	loggedOut bool
}

func New() *Machine {
	return &Machine{ipn: NoState, product: Unavailable}
}

func (m *Machine) OnState(s State) Snapshot {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.ipn = s
	switch s {
	case NeedsLogin:
		m.product = ProdNeedsLogin
	case NeedsMachineAuth:
		m.product = ProdNeedsApproval
	case Starting:
		if m.product != ProdNeedsLogin && m.product != ProdNeedsApproval {
			m.product = ProdStarting
		}
	case Running:
		m.product = ProdRunning
		m.authURL = false
		m.loggedOut = false
	case Stopped:
		if m.loggedOut {
			m.product = ProdStopped
			m.netMap = nil
			m.authURL = false
		} else {
			m.product = ProdStopped
		}
	case NoState:
		if m.product == Unavailable {
			m.product = ProdStarting
		}
	}
	return m.snapLocked()
}

func (m *Machine) OnBrowseToURL() Snapshot {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.authURL = true
	if m.ipn == NeedsLogin || m.product == ProdNeedsLogin {
		m.product = ProdNeedsLogin
	}
	return m.snapLocked()
}

func (m *Machine) OnNetMap(nm NetMap) Snapshot {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.netMap = &nm
	if nm.LockedOut {
		m.product = ProdNeedsApproval
	}
	return m.snapLocked()
}

func (m *Machine) OnLogoutStarted() Snapshot {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.loggedOut = true
	m.product = ProdStopping
	m.authURL = false
	return m.snapLocked()
}

func (m *Machine) OnLogoutCleared() Snapshot {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.loggedOut = true
	m.authURL = false
	m.netMap = nil
	m.ipn = Stopped
	m.product = ProdStopped
	return m.snapLocked()
}

func (m *Machine) OnWorkerCrash() Snapshot {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.product = ProdFailed
	return m.snapLocked()
}

func (m *Machine) Snapshot() Snapshot {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.snapLocked()
}

func (m *Machine) snapLocked() Snapshot {
	var nm *NetMap
	if m.netMap != nil {
		cp := *m.netMap
		nm = &cp
	}
	return Snapshot{
		IPN:            m.ipn,
		Product:        m.product,
		HasAuthURL:     m.authURL,
		AuthURLPending: m.authURL && m.product == ProdNeedsLogin,
		NetMap:         nm,
		LoggedOut:      m.loggedOut,
	}
}

func MapPeerIdentity(n Node) (stableID string, err error) {
	if n.StableID != "" {
		return n.StableID, nil
	}
	if n.NodeID != "" {
		return n.NodeID, errors.New("nodeId present but not a StableNodeID; treat as session-scoped only")
	}
	return "", errors.New("no stable node id; do not persist nodeKey or display name as identity")
}
