import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "H264DecoderPlugin") {
      H264DecoderPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NotificationsPlugin") {
      NotificationsPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TailscaleTransportPlugin") {
      TailscaleTransportPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AudioBackgroundPlugin") {
      AudioBackgroundPlugin.register(with: registrar)
    }

    UNUserNotificationCenter.current().delegate = self
  }

  // Show notification banners (and play sound) even while MonkeyCraft is in the
  // foreground. FlutterAppDelegate's implementation only forwards `willPresent` to
  // registered plugins; with no notification plugin acting as a lifecycle delegate,
  // the completion handler would never fire and iOS would suppress the banner.
  // We present explicitly here instead of calling super.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let sound: UNNotificationPresentationOptions =
      notification.request.content.sound == nil ? [] : [.sound]
    if #available(iOS 14.0, *) {
      var options: UNNotificationPresentationOptions = [.banner, .list]
      options.formUnion(sound)
      completionHandler(options)
    } else {
      var options: UNNotificationPresentationOptions = [.alert]
      options.formUnion(sound)
      completionHandler(options)
    }
  }
}
