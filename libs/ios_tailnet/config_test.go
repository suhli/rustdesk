package tailnet

import "testing"

func TestInvalidControlURLRejectedBeforeStarting(t *testing.T) {
	var node Node
	err := node.Start(t.TempDir(), nil, `{"controlUrl":"file:///etc/hosts"}`)
	if err == nil || err.Error() != "invalid Tailnet control server URL" {
		t.Fatalf("invalid control URL: got %v", err)
	}
}
