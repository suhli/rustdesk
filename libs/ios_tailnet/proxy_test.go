package tailnet

import (
	"context"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestProxyRejectsEveryOtherOriginBeforeDialing(t *testing.T) {
	origin, err := apiOrigin("https://console.example:21114")
	if err != nil {
		t.Fatal(err)
	}
	p := &apiProxy{origin: origin, ctx: context.Background(),
		dial: func(context.Context, string, string) (net.Conn, error) { t.Fatal("unauthorized dial"); return nil, nil }}
	for _, target := range []string{"http://console.example:21114/api/login", "https://other.example:21114/api/login", "https://console.example/api/login", "https://console.example.evil:21114/api/login"} {
		r := httptest.NewRequest("POST", target, strings.NewReader("test-token"))
		w := httptest.NewRecorder()
		p.ServeHTTP(w, r)
		if w.Code != http.StatusForbidden {
			t.Fatalf("%s: %d", target, w.Code)
		}
	}
	r := httptest.NewRequest("CONNECT", "https://other.example:443", nil)
	r.Host = "other.example:443"
	w := httptest.NewRecorder()
	p.ServeHTTP(w, r)
	if w.Code != http.StatusForbidden {
		t.Fatal("arbitrary CONNECT allowed")
	}
}

func TestProxyUsesTailnetDialAndPreservesResponse(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test" || r.URL.Path != "/api/ab" {
			t.Error("request changed")
		}
		if r.Header.Get("Proxy-Authorization") != "" {
			t.Error("proxy credentials leaked")
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		io.WriteString(w, `{"error":"expired"}`)
	}))
	defer upstream.Close()
	origin, err := apiOrigin("http://console.example:21114")
	if err != nil {
		t.Fatal(err)
	}
	called := false
	p := &apiProxy{origin: origin, ctx: context.Background(),
		dial: func(ctx context.Context, network, target string) (net.Conn, error) {
			called = true
			if target != "console.example:21114" {
				t.Fatalf("unexpected target %s", target)
			}
			return (&net.Dialer{}).DialContext(ctx, network, upstream.Listener.Addr().String())
		}}
	r := httptest.NewRequest("GET", "http://console.example:21114/api/ab", nil)
	r.Header.Set("Authorization", "Bearer test")
	r.Header.Set("Proxy-Authorization", "local-only")
	w := httptest.NewRecorder()
	p.ServeHTTP(w, r)
	if !called || w.Code != 401 || w.Body.String() != `{"error":"expired"}` {
		t.Fatalf("unexpected response: %d %s", w.Code, w.Body.String())
	}
}
