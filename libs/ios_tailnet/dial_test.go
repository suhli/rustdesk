package tailnet

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"testing"

	"tailscale.com/ipn/ipnstate"
	"tailscale.com/net/tsdial"
	"tailscale.com/types/key"
)

func TestPrivateNamesNeverUseSystemDNS(t *testing.T) {
	ip := netip.MustParseAddr("100.101.102.103")
	status := &ipnstate.Status{Peer: map[key.NodePublic]*ipnstate.PeerStatus{
		{}: {DNSName: "console.example.ts.net.", TailscaleIPs: []netip.Addr{ip}},
	}}
	for _, address := range []string{"console:21114", "console.example.ts.net:21114", "100.101.102.103:21114"} {
		got, err := resolveTarget(address, status)
		if err != nil || got != netip.AddrPortFrom(ip, 21114) {
			t.Fatalf("configured Tailnet target %s: got %v, %v", address, got, err)
		}
	}
	for _, address := range []string{"localhost:80", "example.com:80", "console.example.ts.net.attacker.test:80", "127.0.0.1:80", "[::1]:80"} {
		if _, err := resolveTarget(address, status); err == nil {
			t.Fatalf("unexpectedly resolved non-Tailnet target %s", address)
		}
	}
}

func TestMissingTailnetRouteNeverUsesHostNetwork(t *testing.T) {
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	target := netip.MustParseAddrPort(listener.Addr().String())
	called := false
	sentinel := errors.New("netstack result")
	dialer := &tsdial.Dialer{
		UseNetstackForIP: func(netip.Addr) bool { return false },
		NetstackDialTCP: func(context.Context, netip.AddrPort) (net.Conn, error) {
			called = true
			return nil, sentinel
		},
	}
	if conn, err := dialNetstack(context.Background(), dialer, target); err == nil || conn != nil || called {
		t.Fatal("an unrouted address must fail even when the host can reach it")
	}
	dialer.UseNetstackForIP = func(netip.Addr) bool { return true }
	if _, err := dialNetstack(context.Background(), dialer, target); !errors.Is(err, sentinel) || !called {
		t.Fatal("routed addresses must use only the netstack dialer")
	}
}
