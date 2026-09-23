package wsframe

import (
	"bytes"
	"testing"
)

func FuzzReadFrame(f *testing.F) {
	f.Add([]byte{0x81, 0x05, 'H', 'e', 'l', 'l', 'o'})
	f.Add([]byte{0x82, 0x7e, 0x00, 0x05, 1, 2, 3, 4, 5})
	f.Add([]byte{0x89, 0x00})
	f.Add([]byte{0x88, 0x02, 0x03, 0xe8})
	f.Add([]byte{0x80, 0x80, 1, 2, 3, 4})
	f.Fuzz(func(t *testing.T, data []byte) {
		if len(data) > 4096 {
			data = data[:4096]
		}
		_, _ = ReadFrame(bytes.NewReader(data), Limits{MaxFrameBytes: 2048, MaxMessageBytes: 2048}, false)
		_, _ = ReadFrame(bytes.NewReader(data), Limits{MaxFrameBytes: 2048, MaxMessageBytes: 2048}, true)
	})
}
