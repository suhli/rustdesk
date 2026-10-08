package tailnet

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"sync"

	"tailscale.com/ipn"
)

// The device-bound Keychain key never goes to disk; state keys are authenticated too.
type encryptedStore struct {
	mu   sync.Mutex
	dir  string
	aead cipher.AEAD
}

func newStore(dir string, key []byte) (*encryptedStore, error) {
	if len(key) != 32 {
		return nil, errors.New("invalid state key")
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	return &encryptedStore{dir: dir, aead: aead}, nil
}

func (s *encryptedStore) path(key ipn.StateKey) string {
	hash := sha256.Sum256([]byte(key))
	return filepath.Join(s.dir, hex.EncodeToString(hash[:])+".enc")
}

func (s *encryptedStore) ReadState(key ipn.StateKey) ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	data, err := os.ReadFile(s.path(key))
	if errors.Is(err, os.ErrNotExist) {
		return nil, ipn.ErrStateNotExist
	}
	if err != nil {
		return nil, err
	}
	n := s.aead.NonceSize()
	if len(data) < n {
		return nil, errors.New("invalid encrypted node identity")
	}
	return s.aead.Open(nil, data[:n], data[n:], []byte(key))
}

func (s *encryptedStore) WriteState(key ipn.StateKey, value []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	nonce := make([]byte, s.aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return err
	}
	data := s.aead.Seal(nonce, nonce, value, []byte(key))
	tmp, err := os.CreateTemp(s.dir, ".state-*")
	if err != nil {
		return err
	}
	name := tmp.Name()
	defer os.Remove(name)
	if _, err = tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err = tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err = tmp.Close(); err != nil {
		return err
	}
	return os.Rename(name, s.path(key))
}
