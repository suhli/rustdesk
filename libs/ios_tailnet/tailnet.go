package tailnet

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"time"

	"tailscale.com/tsnet"
)

type Config struct {
	API        string `json:"api"`
	ID         string `json:"id"`
	Relay      string `json:"relay"`
	ControlURL string `json:"controlUrl"`
}

type Node struct {
	lifecycle sync.Mutex
	mu        sync.Mutex
	server    *tsnet.Server
	proxy     *http.Server
	cancel    context.CancelFunc
	listeners []net.Listener
	ports     [4]int // API, ID, Relay, online query (ID port - 1)
	targets   [4]string
}

func (n *Node) Start(dir string, key []byte, configJSON string) error {
	n.lifecycle.Lock()
	defer n.lifecycle.Unlock()
	if n.server != nil {
		return errors.New("disconnect before changing Tailnet configuration")
	}
	var config Config
	if err := json.Unmarshal([]byte(configJSON), &config); err != nil {
		return err
	}
	if config.ControlURL != "" {
		if _, err := apiOrigin(config.ControlURL); err != nil {
			return errors.New("invalid Tailnet control server URL")
		}
	}
	targets := []string{"", config.ID, config.Relay, ""}
	for _, index := range []int{1, 2} {
		if targets[index] == "" {
			continue
		}
		host, port, err := net.SplitHostPort(targets[index])
		if err != nil || host == "" {
			return errors.New("configure a server hostname and port")
		}
		p, err := strconv.Atoi(port)
		if err != nil || p < 2 || p > 65535 {
			return errors.New("invalid server port")
		}
		if index == 1 {
			targets[3] = net.JoinHostPort(host, strconv.Itoa(p-1))
		}
	}
	if config.API != "" {
		if _, err := apiOrigin(config.API); err != nil {
			return err
		}
	}
	store, err := newStore(filepath.Join(dir, "identity"), key)
	if err != nil {
		return err
	}
	// No diagnostic uploads or auth URLs in local logs.
	if err := os.Setenv("TS_NO_LOGS_NO_SUPPORT", "true"); err != nil {
		return err
	}
	s := &tsnet.Server{Dir: dir, Store: store, Hostname: "rustdesk-ios", ControlURL: config.ControlURL,
		Logf: func(string, ...any) {}, UserLogf: func(string, ...any) {}}
	if err = s.Start(); err != nil {
		s.Close()
		return errors.New("could not start embedded Tailscale")
	}
	ctx, cancel := context.WithCancel(context.Background())
	listeners := make([]net.Listener, 0, 4)
	var ports [4]int
	var proxy *http.Server
	for index, target := range targets {
		if target == "" && !(index == 0 && config.API != "") {
			continue
		}
		listener, err := net.Listen("tcp4", "127.0.0.1:0")
		if err != nil {
			cancel()
			for _, l := range listeners {
				l.Close()
			}
			s.Close()
			return err
		}
		listeners = append(listeners, listener)
		ports[index] = listener.Addr().(*net.TCPAddr).Port
		if index == 0 {
			origin, _ := apiOrigin(config.API) // Validated before starting the node.
			proxy = &http.Server{Handler: &apiProxy{origin: origin, dial: strictDial(s), ctx: ctx},
				ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 64 * 1024,
				ErrorLog: log.New(io.Discard, "", 0)}
			go func(server *http.Server) {
				if err := server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
					cancel()
				}
			}(proxy)
		} else {
			go forwardTCP(ctx, listener, target, strictDial(s))
		}
	}
	n.server, n.proxy, n.cancel, n.listeners = s, proxy, cancel, listeners
	n.mu.Lock()
	defer n.mu.Unlock()
	n.ports = ports
	copy(n.targets[:], targets)
	n.targets[0] = config.API
	return nil
}

// Reject stale forwarding configuration after the user edits server settings.
func (n *Node) Port(role int, target string) int {
	n.mu.Lock()
	defer n.mu.Unlock()
	if role < 0 || role >= len(n.targets) || n.ports[role] == 0 {
		return 0
	}
	if role == 0 {
		a, err := apiOrigin(target)
		if err != nil {
			return 0
		}
		b, err := apiOrigin(n.targets[0])
		if err != nil {
			return 0
		}
		if a.Scheme != b.Scheme || authority(a) != authority(b) {
			return 0
		}
	} else if target != n.targets[role] {
		return 0
	}
	return n.ports[role]
}

func (n *Node) Stop() error {
	n.lifecycle.Lock()
	defer n.lifecycle.Unlock()
	if n.server == nil {
		return nil
	}
	n.mu.Lock()
	n.ports = [4]int{}
	n.mu.Unlock()
	n.cancel()
	var err error
	if n.proxy != nil {
		err = n.proxy.Close()
	}
	for _, listener := range n.listeners {
		listener.Close()
	}
	err = errors.Join(err, n.server.Close())
	n.server, n.proxy, n.cancel, n.listeners = nil, nil, nil, nil
	return err
}

func (n *Node) Status() (string, error) {
	n.lifecycle.Lock()
	defer n.lifecycle.Unlock()
	if n.server == nil {
		return `{"state":"Stopped"}`, nil
	}
	client, err := n.server.LocalClient()
	if err != nil {
		return "", err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	status, err := client.StatusWithoutPeers(ctx)
	if err != nil {
		return "", errors.New("could not read Tailnet status")
	}
	name := n.server.Hostname
	// Before authorization, Self.HostName is the OS hostname, often localhost on iOS.
	if status.Self != nil && status.Self.InNetworkMap && status.Self.HostName != "" {
		name = status.Self.HostName
	}
	data, err := json.Marshal(map[string]any{"state": status.BackendState,
		"authUrl": status.AuthURL, "name": name, "ips": status.TailscaleIPs})
	return string(data), err
}
