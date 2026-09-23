import AVFAudio
import Flutter
import UIKit

final class AudioBackgroundPlugin: NSObject, FlutterPlugin {
  private var active = false
  private var diagnosticEvents: [[String: Any]] = []
  private var diagnosticObservers: [NSObjectProtocol] = []

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "monkeycraft/audio_background", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AudioBackgroundPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "diagnostic":
      startDiagnosticObservers()
      recordDiagnostic(call.arguments as? [String: Any] ?? ["event": "invalid"])
      var resume = false
      if let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
        let request = directory.appendingPathComponent("monkeycraft-audio-resume-once")
        if FileManager.default.fileExists(atPath: request.path) {
          do {
            try FileManager.default.removeItem(at: request)
            resume = true
            recordDiagnostic(["event": "manual-context-resume-request"])
          } catch {}
        }
      }
      result(resume)
    case "start":
      if !active {
        do {
          let session = AVAudioSession.sharedInstance()
          try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
          try session.setActive(true)
          active = true
        } catch {
          result(FlutterError(code: "audio_background_start", message: "Unable to activate audio session", details: nil))
          return
        }
      }
      result(nil)
    case "stop":
      if active {
        do { try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation]) }
        catch { result(FlutterError(code: "audio_background_stop", message: "Unable to deactivate audio session", details: nil)); return }
        active = false
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startDiagnosticObservers() {
    guard diagnosticObservers.isEmpty else { return }
    let events: [(Notification.Name, String)] = [
      (UIApplication.didBecomeActiveNotification, "native-active"),
      (UIApplication.willResignActiveNotification, "native-inactive"),
      (UIApplication.didEnterBackgroundNotification, "native-background"),
      (AVAudioSession.interruptionNotification, "native-interruption"),
      (AVAudioSession.routeChangeNotification, "native-route-change"),
      (AVAudioSession.mediaServicesWereResetNotification, "native-media-reset"),
    ]
    for (name, event) in events {
      diagnosticObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
        var entry: [String: Any] = ["event": event]
        for (key, field) in [
          (AVAudioSessionInterruptionTypeKey, "interruptionType"),
          (AVAudioSessionInterruptionOptionKey, "interruptionOptions"),
          (AVAudioSessionRouteChangeReasonKey, "routeReason"),
        ] {
          if let value = notification.userInfo?[key] as? NSNumber { entry[field] = value }
        }
        self?.recordDiagnostic(entry)
      })
    }
  }

  private func recordDiagnostic(_ data: [String: Any]) {
    let session = AVAudioSession.sharedInstance()
    var entry = data
    entry["atMs"] = Int64(Date().timeIntervalSince1970 * 1000)
    entry["leaseActive"] = active
    entry["category"] = session.category.rawValue
    entry["mode"] = session.mode.rawValue
    entry["outputVolume"] = session.outputVolume
    entry["otherAudio"] = session.isOtherAudioPlaying
    entry["secondaryAudioSilenced"] = session.secondaryAudioShouldBeSilencedHint
    entry["outputs"] = session.currentRoute.outputs.map { $0.portType.rawValue }
    diagnosticEvents.append(entry)
    if diagnosticEvents.count > 160 { diagnosticEvents.removeFirst(diagnosticEvents.count - 160) }
    guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
          let encoded = try? JSONSerialization.data(withJSONObject: diagnosticEvents, options: [.sortedKeys]) else { return }
    try? encoded.write(to: directory.appendingPathComponent("monkeycraft-audio-diagnostics.json"), options: .atomic)
  }

  deinit {
    for observer in diagnosticObservers { NotificationCenter.default.removeObserver(observer) }
  }
}
