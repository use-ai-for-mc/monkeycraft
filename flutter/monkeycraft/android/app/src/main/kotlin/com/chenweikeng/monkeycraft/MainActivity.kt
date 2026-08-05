package com.chenweikeng.monkeycraft

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
  private var h264Plugin: H264DecoderPlugin? = null
  private var notificationsPlugin: NotificationsPlugin? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    h264Plugin = H264DecoderPlugin(flutterEngine.renderer, flutterEngine.dartExecutor.binaryMessenger)
    notificationsPlugin = NotificationsPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
  }

  override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
    h264Plugin?.dispose()
    h264Plugin = null
    notificationsPlugin?.dispose()
    notificationsPlugin = null
    super.cleanUpFlutterEngine(flutterEngine)
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray,
  ) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    notificationsPlugin?.onRequestPermissionsResult(requestCode, permissions, grantResults)
  }
}
