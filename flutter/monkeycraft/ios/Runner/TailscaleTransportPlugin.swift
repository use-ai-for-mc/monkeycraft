import Flutter
import Foundation

final class TailscaleEventStreamHandler: NSObject, FlutterStreamHandler {
  var sink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}

final class TailscaleTransportPlugin: NSObject, FlutterPlugin {
  private let manager: TailscaleNodeManager
  private let bridge: TailscaleLoopbackBridge
  private let events = TailscaleEventStreamHandler()

  init(manager: TailscaleNodeManager, bridge: TailscaleLoopbackBridge = TailscaleLoopbackBridge()) {
    self.manager = manager
    self.bridge = bridge
    super.init()
    manager.onSnapshot = { [weak self] snapshot in
      DispatchQueue.main.async {
        self?.events.sink?(snapshot.asMap())
      }
    }
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "monkeycraft/tailscale",
      binaryMessenger: registrar.messenger()
    )
    let eventChannel = FlutterEventChannel(
      name: "monkeycraft/tailscale_events",
      binaryMessenger: registrar.messenger()
    )
    let manager = TailscaleNodeManager(
      backendFactory: {
        #if MONKEYCRAFT_HAS_LIBTAILSCALE
        return LibtailscaleBackend()
        #else
        return nil
        #endif
      },
      presenter: SystemAuthPresenter()
    )
    let instance = TailscaleTransportPlugin(manager: manager)
    registrar.addMethodCallDelegate(instance, channel: channel)
    eventChannel.setStreamHandler(instance.events)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let finish: FlutterResult = { value in
      DispatchQueue.main.async { result(value) }
    }
    manager.queue.async { [weak self] in
      guard let self else {
        finish(FlutterError(code: "gone", message: "plugin deallocated", details: nil))
        return
      }
      self.handleOnQueue(call, result: finish)
    }
  }

  private func handleOnQueue(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "diagnostics":
      result(Self.diagnostics())
    case "status":
      result(manager.currentSnapshot().asMap())
    case "start":
      manager.start()
      result(manager.currentSnapshot().asMap())
    case "loginInteractive":
      manager.loginInteractive()
      result(nil)
    case "cancel":
      manager.cancel()
      result(nil)
    case "logout":
      manager.logout()
      result(nil)
    case "stop":
      manager.stop()
      bridge.closeAll()
      result(nil)
    case "listPeers":
      result(manager.currentSnapshot().peers.map { $0.asMap() })
    case "openBridge":
      let args = (call.arguments as? [String: Any]) ?? [:]
      let nodeId = args["nodeId"] as? String ?? ""
      let port = args["port"] as? Int ?? 9600
      do {
        guard let backend = manager.backendForDial() else {
          throw TailscaleBridgeError.notRunning
        }
        let lease = try bridge.open(
          nodeId: nodeId,
          port: port,
          snapshot: manager.currentSnapshot(),
          peers: manager.currentSnapshot().peers,
          dialer: backend
        )
        result(["url": lease.url, "leaseId": lease.leaseId])
      } catch let error as TailscaleBridgeError {
        result(
          FlutterError(
            code: String(describing: error),
            message: TailscaleNodeManager.redact("\(error)"),
            details: nil
          )
        )
      } catch {
        result(
          FlutterError(
            code: "dialFailed",
            message: TailscaleNodeManager.redact(error.localizedDescription),
            details: nil
          )
        )
      }
    case "closeBridge":
      let args = (call.arguments as? [String: Any]) ?? [:]
      do {
        try bridge.close(leaseId: args["leaseId"] as? String)
        result(nil)
      } catch let error as TailscaleBridgeError where error == .unknownLease {
        result(nil)
      } catch {
        result(FlutterError(code: "unknown_lease", message: "unknown lease", details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func diagnostics() -> [String: Any] {
    #if MONKEYCRAFT_HAS_LIBTAILSCALE
    let linked = true
    let statusJSON = true
    let reason = "libtailscale linked"
    #else
    let linked = false
    let statusJSON = false
    let reason = "libtailscale archive missing; run ios/third_party/libtailscale/build.sh"
    #endif
    return [
      "available": linked,
      "libtailscaleLinked": linked,
      "statusJsonAvailable": statusJSON,
      "reason": reason,
      "symbols": [
        "tailscale_new",
        "tailscale_start",
        "tailscale_status_json",
        "tailscale_loopback",
        "tailscale_dial",
        "tailscale_close",
      ],
      "libtailscaleCommit": MONKEYCRAFT_LIBTAILSCALE_COMMIT,
      "tailscaleGoModule": MONKEYCRAFT_TAILSCALE_GO_MODULE,
      "deploymentTarget": MONKEYCRAFT_APP_IOS_MIN,
      "kitIosMinimum": MONKEYCRAFT_TAILSCALEKIT_IOS_MIN,
    ]
  }
}
