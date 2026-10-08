package tailnet

import (
	"bytes"
	"os"
	"testing"
)

func TestEncryptedIdentityRestoresAndRejectsTampering(t *testing.T) {
	dir := t.TempDir()
	key := bytes.Repeat([]byte{42}, 32)
	store, err := newStore(dir, key)
	if err != nil {
		t.Fatal(err)
	}
	secret := []byte("test-node-private-key")
	if err = store.WriteState("node", secret); err != nil {
		t.Fatal(err)
	}
	restored, err := newStore(dir, key)
	if err != nil {
		t.Fatal(err)
	}
	data, err := restored.ReadState("node")
	if err != nil || !bytes.Equal(data, secret) {
		t.Fatalf("identity restore: %v", err)
	}
	ciphertext, err := os.ReadFile(store.path("node"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(ciphertext, secret) {
		t.Fatal("plaintext identity on disk")
	}
	ciphertext[len(ciphertext)-1] ^= 1
	if err = os.WriteFile(store.path("node"), ciphertext, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err = restored.ReadState("node"); err == nil {
		t.Fatal("tampered identity accepted")
	}
}
