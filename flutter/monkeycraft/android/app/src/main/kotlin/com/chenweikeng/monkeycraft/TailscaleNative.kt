package com.chenweikeng.monkeycraft

object TailscaleNative {
  val available: Boolean = try {
    System.loadLibrary("tailscale_monkeycraft")
    System.loadLibrary("tailscale_jni")
    true
  } catch (_: UnsatisfiedLinkError) {
    false
  }
  external fun configure(dataDir: String): Int
  external fun newNode(): Int
  external fun setDir(handle: Int, path: String): Int
  external fun setHostname(handle: Int, hostname: String): Int
  external fun start(handle: Int): Int
  external fun close(handle: Int): Int
  external fun error(handle: Int): String
  external fun status(handle: Int): String?
  external fun loopback(handle: Int): Array<String>?
  external fun dial(handle: Int, network: String, address: String, timeoutMillis: Int): Int
}
