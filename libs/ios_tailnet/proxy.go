package tailnet

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

func apiOrigin(raw string) (*url.URL, error) {
	u, err := url.Parse(raw)
	if err != nil || u.Hostname() == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Scheme != "http" && u.Scheme != "https") {
		return nil, errors.New("configure an HTTP or HTTPS API server without credentials or query")
	}
	return u, nil
}

func authority(u *url.URL) string {
	port := u.Port()
	if port == "" {
		if u.Scheme == "https" {
			port = "443"
		} else {
			port = "80"
		}
	}
	return net.JoinHostPort(strings.ToLower(u.Hostname()), port)
}

type apiProxy struct {
	origin *url.URL
	dial   func(context.Context, string, string) (net.Conn, error)
	ctx    context.Context
}

func (p *apiProxy) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	connect := r.Method == http.MethodConnect
	allowed := !connect && r.URL.Scheme == p.origin.Scheme && authority(r.URL) == authority(p.origin) && r.URL.User == nil
	if connect {
		allowed = p.origin.Scheme == "https" && strings.EqualFold(r.Host, authority(p.origin))
	}
	if !allowed {
		http.Error(w, "Tailnet target is not allowed", http.StatusForbidden)
		return
	}
	ctx, cancel := context.WithTimeout(p.ctx, 30*time.Second)
	defer cancel()
	if connect {
		upstream, err := p.dial(ctx, "tcp", authority(p.origin))
		if err != nil {
			http.Error(w, "Tailnet is unavailable; reconnect and retry", http.StatusBadGateway)
			return
		}
		defer upstream.Close()
		client, buffered, err := w.(http.Hijacker).Hijack()
		if err != nil {
			return
		}
		defer client.Close()
		stop := context.AfterFunc(ctx, func() { client.Close(); upstream.Close() })
		defer stop()
		if _, err = buffered.WriteString("HTTP/1.1 200 Connection Established\r\n\r\n"); err != nil {
			return
		}
		if err = buffered.Flush(); err != nil {
			return
		}
		done := make(chan struct{})
		go func() { io.Copy(upstream, buffered); upstream.Close(); close(done) }()
		io.Copy(client, upstream)
		client.Close()
		<-done
		return
	}
	transport := &http.Transport{DialContext: p.dial, DisableKeepAlives: true,
		ResponseHeaderTimeout: 20 * time.Second}
	defer transport.CloseIdleConnections()
	request := r.Clone(ctx)
	request.RequestURI = ""
	stripHopHeaders(request.Header)
	response, err := transport.RoundTrip(request)
	if err != nil {
		http.Error(w, "Tailnet is unavailable; reconnect and retry", http.StatusBadGateway)
		return
	}
	defer response.Body.Close()
	stripHopHeaders(response.Header)
	for key, values := range response.Header {
		for _, value := range values {
			w.Header().Add(key, value)
		}
	}
	w.WriteHeader(response.StatusCode)
	io.Copy(w, response.Body)
}

func stripHopHeaders(headers http.Header) {
	for _, key := range strings.Split(headers.Get("Connection"), ",") {
		headers.Del(strings.TrimSpace(key))
	}
	for _, key := range []string{"Connection", "Proxy-Connection", "Proxy-Authorization", "Proxy-Authenticate", "Keep-Alive", "TE", "Trailer", "Transfer-Encoding", "Upgrade"} {
		headers.Del(key)
	}
}

func forwardTCP(ctx context.Context, listener net.Listener, target string,
	dial func(context.Context, string, string) (net.Conn, error)) {
	for {
		client, err := listener.Accept()
		if err != nil {
			return
		}
		go func() {
			defer client.Close()
			dialCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
			upstream, err := dial(dialCtx, "tcp", target)
			cancel()
			if err != nil {
				return
			}
			defer upstream.Close()
			stop := context.AfterFunc(ctx, func() { client.Close(); upstream.Close() })
			defer stop()
			done := make(chan struct{})
			go func() { io.Copy(upstream, client); upstream.Close(); close(done) }()
			io.Copy(client, upstream)
			client.Close()
			<-done
		}()
	}
}
