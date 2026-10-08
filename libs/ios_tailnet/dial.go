package tailnet

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"strconv"
	"strings"

	"tailscale.com/ipn/ipnstate"
	"tailscale.com/net/tsdial"
	"tailscale.com/tsnet"
)

// Server.Dial may fall back to the host network. Only the pinned SDK's
// netstack dialer is suitable here; never resolve private names with host DNS.
func strictDial(server *tsnet.Server) func(context.Context, string, string) (net.Conn, error) {
	return func(ctx context.Context, network, address string) (net.Conn, error) {
		if network != "tcp" && network != "tcp4" && network != "tcp6" {
			return nil, errors.New("Tailnet forwarding supports TCP only")
		}
		client, err := server.LocalClient()
		if err != nil {
			return nil, errors.New("Tailnet is unavailable")
		}
		status, err := client.Status(ctx)
		if err != nil || status.BackendState != "Running" {
			return nil, errors.New("Tailnet is not connected")
		}
		target, err := resolveTarget(address, status)
		if err != nil {
			return nil, err
		}
		dialer, ok := server.Sys().Dialer.GetOK()
		if !ok {
			return nil, errors.New("Tailnet is unavailable")
		}
		return dialNetstack(ctx, dialer, target)
	}
}

func dialNetstack(ctx context.Context, dialer *tsdial.Dialer, target netip.AddrPort) (net.Conn, error) {
	if dialer.UseNetstackForIP == nil || dialer.NetstackDialTCP == nil ||
		!dialer.UseNetstackForIP(target.Addr()) {
		return nil, errors.New("no Tailnet route to the configured server")
	}
	return dialer.NetstackDialTCP(ctx, target)
}

func resolveTarget(address string, status *ipnstate.Status) (netip.AddrPort, error) {
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return netip.AddrPort{}, errors.New("invalid Tailnet server address")
	}
	p, err := strconv.ParseUint(port, 10, 16)
	if err != nil || p == 0 {
		return netip.AddrPort{}, errors.New("invalid Tailnet server port")
	}
	ip, err := netip.ParseAddr(host)
	if err == nil {
		if ip.Zone() != "" || ip.IsLoopback() || ip.IsUnspecified() || ip.IsMulticast() {
			return netip.AddrPort{}, errors.New("invalid Tailnet server IP")
		}
		return netip.AddrPortFrom(ip.Unmap(), uint16(p)), nil
	}
	host = strings.ToLower(strings.TrimSuffix(host, "."))
	for _, peer := range status.Peer {
		name := strings.ToLower(strings.TrimSuffix(peer.DNSName, "."))
		if name == "" || (host != name && host != strings.SplitN(name, ".", 2)[0]) || len(peer.TailscaleIPs) == 0 {
			continue
		}
		if ip.IsValid() {
			return netip.AddrPort{}, errors.New("ambiguous Tailnet server name; use its full MagicDNS name")
		}
		ip = peer.TailscaleIPs[0]
	}
	if !ip.IsValid() {
		return netip.AddrPort{}, errors.New("server is not in the Tailnet map; use a Tailnet IP or MagicDNS name")
	}
	return netip.AddrPortFrom(ip, uint16(p)), nil
}
