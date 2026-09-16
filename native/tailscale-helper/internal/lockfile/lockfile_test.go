package lockfile

import (
	"testing"
)

func TestAcquireExclusive(t *testing.T) {
	dir := t.TempDir()
	a, err := Acquire(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer a.Close()
	_, err = Acquire(dir)
	if err == nil {
		t.Fatal("expected second lock to fail")
	}
	if err := a.Close(); err != nil {
		t.Fatal(err)
	}
	b, err := Acquire(dir)
	if err != nil {
		t.Fatal(err)
	}
	_ = b.Close()
}
