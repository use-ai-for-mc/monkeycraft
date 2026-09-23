package backend

import (
	"testing"

	"tailscale.com/ipn"
)

func TestEventFromNotifyBrowseToURL(t *testing.T) {
	url := "https://login.tailscale.com/a/not-a-real-token"
	st := ipn.NeedsLogin
	ev := eventFromNotify(ipn.Notify{
		State:       &st,
		BrowseToURL: &url,
	})
	if ev.State != StateNeedsLogin {
		t.Fatalf("state %s", ev.State)
	}
	if ev.AuthURL != url {
		t.Fatalf("missing structured auth url")
	}
}

func TestEventFromNotifyBrowseToURLWithoutStateNeedsLogin(t *testing.T) {
	url := "https://login.tailscale.com/a/not-a-real-token"
	ev := eventFromNotify(ipn.Notify{BrowseToURL: &url})
	if ev.State != StateNeedsLogin || ev.Status.State != StateNeedsLogin {
		t.Fatalf("BrowseToURL state = %q / %q, want needsLogin", ev.State, ev.Status.State)
	}
	if ev.AuthURL != url || ev.Status.AuthURL != url {
		t.Fatal("missing structured auth url")
	}
}

func TestMapIPNStates(t *testing.T) {
	cases := map[ipn.State]State{
		ipn.NeedsLogin:       StateNeedsLogin,
		ipn.NeedsMachineAuth: StateNeedsApproval,
		ipn.Running:          StateRunning,
		ipn.Starting:         StateStarting,
		ipn.Stopped:          StateStopped,
	}
	for in, want := range cases {
		if got := mapIPNState(in, ""); got != want {
			t.Fatalf("%v: got %s want %s", in, got, want)
		}
	}
}
