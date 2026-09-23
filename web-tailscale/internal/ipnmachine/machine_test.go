package ipnmachine

import "testing"

func TestLoginFlow(t *testing.T) {
	m := New()
	s := m.OnState(NeedsLogin)
	if s.Product != ProdNeedsLogin {
		t.Fatalf("%s", s.Product)
	}
	s = m.OnBrowseToURL()
	if !s.HasAuthURL || !s.AuthURLPending {
		t.Fatalf("%+v", s)
	}
	s = m.OnState(Running)
	if s.Product != ProdRunning || s.HasAuthURL {
		t.Fatalf("%+v", s)
	}
	online := true
	s = m.OnNetMap(NetMap{
		Self:  Node{Name: "web", StableID: "nStableSelf", Addresses: []string{"100.64.0.2"}},
		Peers: []Node{{Name: "pc", StableID: "nStablePC", Addresses: []string{"100.64.0.1"}, Online: &online}},
	})
	if s.NetMap == nil || s.NetMap.Peers[0].StableID != "nStablePC" {
		t.Fatalf("%+v", s.NetMap)
	}
	s = m.OnLogoutStarted()
	if s.Product != ProdStopping {
		t.Fatalf("%s", s.Product)
	}
	s = m.OnLogoutCleared()
	if s.Product != ProdStopped || s.NetMap != nil || s.HasAuthURL {
		t.Fatalf("%+v", s)
	}
}

func TestNeedsApproval(t *testing.T) {
	m := New()
	s := m.OnState(NeedsMachineAuth)
	if s.Product != ProdNeedsApproval {
		t.Fatalf("%s", s.Product)
	}
}

func TestMapPeerIdentity(t *testing.T) {
	id, err := MapPeerIdentity(Node{StableID: "abc"})
	if err != nil || id != "abc" {
		t.Fatalf("%s %v", id, err)
	}
	if _, err := MapPeerIdentity(Node{Name: "pc", NodeKey: "nodekey:xx"}); err == nil {
		t.Fatal("must not accept name/nodeKey as identity")
	}
}

func TestWorkerCrash(t *testing.T) {
	m := New()
	if m.OnWorkerCrash().Product != ProdFailed {
		t.Fatal("expected failed")
	}
}
