// Fixed public test material. Never use these keys or nonces in production.
package main
import("crypto/ecdh";"encoding/hex";"fmt";"golang.org/x/crypto/chacha20poly1305";"golang.org/x/crypto/blake2s";"golang.org/x/crypto/nacl/box")
func emit(n string,b []byte){fmt.Printf("%s=%s\n",n,hex.EncodeToString(b))}
func main(){
 var a,b [32]byte;for i:=range a{a[i]=byte(i+1);b[i]=byte(32+i)}
 ak,_:=ecdh.X25519().NewPrivateKey(a[:]);bk,_:=ecdh.X25519().NewPrivateKey(b[:]);secret,_:=ak.ECDH(bk.PublicKey());emit("aPrivate",a[:]);emit("bPublic",bk.PublicKey().Bytes());emit("shared",secret)
 plain:=[]byte("MonkeyCraft public crypto interoperability vector");emit("plain",plain)
 var n12 [12]byte;n12[4]=7;emit("nonce12",n12[:]);emit("aeadKey",a[:]);ae,_:=chacha20poly1305.New(a[:]);emit("aead",ae.Seal(nil,n12[:],plain,nil))
 h:=blake2s.Sum256(plain);emit("blake2s",h[:])
 var n24 [24]byte;for i:=range n24{n24[i]=byte(i)};var pub [32]byte;copy(pub[:],bk.PublicKey().Bytes());emit("nonce24",n24[:]);emit("box",box.Seal(nil,plain,&n24,&pub,&a)); x,_:=chacha20poly1305.NewX(a[:]);emit("xaead",x.Seal(nil,n24[:],plain,[]byte("cookie-mac1")))
}
