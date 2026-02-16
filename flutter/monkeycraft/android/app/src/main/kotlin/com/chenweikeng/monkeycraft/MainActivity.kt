package com.chenweikeng.monkeycraft

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
  private var h264Plugin: H264DecoderPlugin? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    h264Plugin = H264DecoderPlugin(flutterEngine.renderer, flutterEngine.dartExecutor.binaryMessenger)
  }

  override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
    h264Plugin?.dispose()
    h264Plugin = null
    super.cleanUpFlutterEngine(flutterEngine)
  }
}
