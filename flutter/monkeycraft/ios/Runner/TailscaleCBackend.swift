import Foundation
#if canImport(UIKit)
import UIKit
#endif

final class SystemAuthPresenter: NSObject, TailscaleAuthPresenter {
  private let opener: (URL, @escaping (Bool) -> Void) -> Void

  override init() {
    opener = { url, completion in
      UIApplication.shared.open(url, options: [:], completionHandler: completion)
    }
    super.init()
  }

  init(opener: @escaping (URL, @escaping (Bool) -> Void) -> Void) {
    self.opener = opener
    super.init()
  }

  func presentAuthURL(_ url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
    TailscaleTiming.instant("systemOpen.entry")
    DispatchQueue.main.async {
      self.opener(url) { opened in
        TailscaleTiming.instant(opened ? "systemOpen.complete" : "systemOpen.failed")
        if opened {
          completion(.success(()))
        } else {
          completion(
            .failure(
              NSError(domain: "monkeycraft.tailscale", code: 6, userInfo: [
                NSLocalizedDescriptionKey: "could not open Tailscale sign-in page",
              ])
            )
          )
        }
      }
    }
  }
}

#if MONKEYCRAFT_HAS_LIBTAILSCALE

final class LibtailscaleBackend: TailscaleNodeBackend, TailscaleDialer {
  private var handle: Int32 = -1
  private let hostname: String
  private let timingReporter: (String, DispatchTime) -> Void
  #if MONKEYCRAFT_TAILSCALE_DIAGNOSTIC_ARCHIVE
  private var lastDiagnosticSequence: UInt64 = 0
  #endif

  init(
    hostname: String = "monkeycraft-ios",
    timingReporter: @escaping (String, DispatchTime) -> Void = TailscaleTiming.defaultRecord
  ) {
    self.hostname = hostname
    self.timingReporter = timingReporter
  }

  func startNode(stateDirectory: URL) throws {
    let createdAt = DispatchTime.now()
    handle = tailscale_new()
    record("tailscale_new", startedAt: createdAt)
    guard handle >= 0 else {
      throw NSError(domain: "monkeycraft.tailscale", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "tailscale_new failed",
      ])
    }
    tailscale_set_logfd(handle, -1)
    #if MONKEYCRAFT_TAILSCALE_DIAGNOSTIC_ARCHIVE
    tailscale_diagnostic_reset()
    lastDiagnosticSequence = 0
    #endif
    let dirResult = stateDirectory.path.withCString { tailscale_set_dir(handle, $0) }
    guard dirResult == 0 else { throw posixError("set_dir") }
    let hostResult = hostname.withCString { tailscale_set_hostname(handle, $0) }
    guard hostResult == 0 else { throw posixError("set_hostname") }
    let control = "https://controlplane.tailscale.com"
    let controlResult = control.withCString { tailscale_set_control_url(handle, $0) }
    guard controlResult == 0 else { throw posixError("set_control_url") }
    tailscale_set_ephemeral(handle, 0)
    let startedAt = DispatchTime.now()
    let startResult = tailscale_start(handle)
    record("tailscale_start", startedAt: startedAt)
    guard startResult == 0 else { throw posixError("start") }
  }

  func statusJSON() throws -> Data {
    var out: UnsafeMutablePointer<CChar>?
    let startedAt = DispatchTime.now()
    let result = tailscale_status_json(handle, &out)
    record("tailscale_status_json", startedAt: startedAt)
    guard result == 0, let out else { throw posixError("status_json") }
    defer { free(out) }
    #if MONKEYCRAFT_TAILSCALE_DIAGNOSTIC_ARCHIVE
    appendNativeDiagnostics()
    #endif
    return Data(bytes: out, count: strlen(out))
  }

  func loginInteractive() throws {
    let startedAt = DispatchTime.now()
    let loop = try loopback()
    record("tailscale_loopback", startedAt: startedAt)
    try postLocalAPI(path: "/localapi/v0/login-interactive", loopback: loop)
  }

  func logout() throws {
    let loop = try loopback()
    try postLocalAPI(path: "/localapi/v0/logout", loopback: loop)
  }

  func close() {
    if handle >= 0 {
      tailscale_close(handle)
      handle = -1
    }
  }

  func dial(address: String) throws -> Int32 {
    var conn: Int32 = 0
    let result = address.withCString { addr in
      "tcp".withCString { proto in
        tailscale_dial(handle, proto, addr, &conn)
      }
    }
    guard result == 0 else { throw posixError("dial") }
    return conn
  }

  private struct Loopback {
    let address: String
    let localAPIKey: String
  }

  private func loopback() throws -> Loopback {
    let addr = UnsafeMutablePointer<CChar>.allocate(capacity: 64)
    let proxy = UnsafeMutablePointer<CChar>.allocate(capacity: 33)
    let api = UnsafeMutablePointer<CChar>.allocate(capacity: 33)
    defer {
      addr.deallocate()
      proxy.deallocate()
      api.deallocate()
    }
    let result = tailscale_loopback(handle, addr, 64, proxy, api)
    guard result == 0 else { throw posixError("loopback") }
    return Loopback(address: String(cString: addr), localAPIKey: String(cString: api))
  }

  private func postLocalAPI(path: String, loopback: Loopback) throws {
    let parts = loopback.address.split(separator: ":")
    guard parts.count == 2, let port = Int(parts[1]) else {
      throw NSError(domain: "monkeycraft.tailscale", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "invalid loopback address",
      ])
    }
    var components = URLComponents()
    components.scheme = "http"
    components.host = String(parts[0])
    components.port = port
    components.path = path
    guard let url = components.url else {
      throw NSError(domain: "monkeycraft.tailscale", code: 3, userInfo: [
        NSLocalizedDescriptionKey: "cannot build localapi url",
      ])
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    let token = Data("tsnet:\(loopback.localAPIKey)".utf8).base64EncodedString()
    request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("localapi", forHTTPHeaderField: "Sec-Tailscale")
    let semaphore = DispatchSemaphore(value: 0)
    var capturedError: Error?
    let startedAt = DispatchTime.now()
    URLSession.shared.dataTask(with: request) { _, response, error in
      if let error {
        capturedError = error
      } else if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
        capturedError = NSError(domain: "monkeycraft.tailscale", code: http.statusCode, userInfo: [
          NSLocalizedDescriptionKey: "localapi status \(http.statusCode)",
        ])
      }
      self.record("localapi_request", startedAt: startedAt)
      semaphore.signal()
    }.resume()
    if semaphore.wait(timeout: .now() + 20) == .timedOut {
      throw NSError(domain: "monkeycraft.tailscale", code: 4, userInfo: [
        NSLocalizedDescriptionKey: "localapi timeout",
      ])
    }
    if let capturedError { throw capturedError }
  }

  private func posixError(_ op: String) -> NSError {
    var buf = [CChar](repeating: 0, count: 2048)
    _ = tailscale_errmsg(handle, &buf, 2048)
    let detail = TailscaleNodeManager.redact(String(cString: buf))
    return NSError(domain: "monkeycraft.tailscale", code: -1, userInfo: [
      NSLocalizedDescriptionKey: "\(op) failed: \(detail)",
    ])
  }

  private func record(_ stage: String, startedAt: DispatchTime) {
    timingReporter(stage, startedAt)
  }

  #if MONKEYCRAFT_TAILSCALE_DIAGNOSTIC_ARCHIVE
  private func appendNativeDiagnostics() {
    var out: UnsafeMutablePointer<CChar>?
    guard tailscale_diagnostic_json(&out) == 0, let out else { return }
    defer { free(out) }
    guard let object = try? JSONSerialization.jsonObject(with: Data(bytes: out, count: strlen(out))) as? [String: Any],
      let events = object["events"] as? [[String: Any]]
    else { return }
    for event in events {
      guard let sequence = event["sequence"] as? NSNumber,
        sequence.uint64Value > lastDiagnosticSequence,
        let stage = event["stage"] as? NSNumber,
        let elapsed = event["elapsedMs"] as? NSNumber,
        let offset = event["offsetMs"] as? NSNumber,
        let attempt = event["attempt"] as? NSNumber,
        let status = event["status"] as? NSNumber
      else { continue }
      lastDiagnosticSequence = sequence.uint64Value
      TailscaleTiming.native(
        stage: stage.uint8Value,
        elapsedMs: elapsed.int64Value,
        offsetMs: offset.int64Value,
        attempt: attempt.uint64Value,
        status: status.intValue
      )
    }
  }
  #endif
}

#endif
