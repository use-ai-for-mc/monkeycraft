import Foundation
#if canImport(UIKit)
import UIKit
#endif

final class SystemAuthPresenter: NSObject, TailscaleAuthPresenter {
  func presentAuthURL(_ url: URL) throws {
    DispatchQueue.main.async {
      UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
  }
}

#if MONKEYCRAFT_HAS_LIBTAILSCALE

final class LibtailscaleBackend: TailscaleNodeBackend, TailscaleDialer {
  private var handle: Int32 = -1
  private let hostname: String

  init(hostname: String = "monkeycraft-ios") {
    self.hostname = hostname
  }

  func startNode(stateDirectory: URL) throws {
    handle = tailscale_new()
    guard handle >= 0 else {
      throw NSError(domain: "monkeycraft.tailscale", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "tailscale_new failed",
      ])
    }
    #if DEBUG
    tailscale_set_logfd(handle, 2)
    #else
    tailscale_set_logfd(handle, -1)
    #endif
    let dirResult = stateDirectory.path.withCString { tailscale_set_dir(handle, $0) }
    guard dirResult == 0 else { throw posixError("set_dir") }
    let hostResult = hostname.withCString { tailscale_set_hostname(handle, $0) }
    guard hostResult == 0 else { throw posixError("set_hostname") }
    let control = "https://controlplane.tailscale.com"
    let controlResult = control.withCString { tailscale_set_control_url(handle, $0) }
    guard controlResult == 0 else { throw posixError("set_control_url") }
    tailscale_set_ephemeral(handle, 0)
    let startResult = tailscale_start(handle)
    guard startResult == 0 else { throw posixError("start") }
  }

  func statusJSON() throws -> Data {
    var out: UnsafeMutablePointer<CChar>?
    let result = tailscale_status_json(handle, &out)
    guard result == 0, let out else { throw posixError("status_json") }
    defer { free(out) }
    return Data(bytes: out, count: strlen(out))
  }

  func loginInteractive() throws {
    let loop = try loopback()
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
    URLSession.shared.dataTask(with: request) { _, response, error in
      if let error {
        capturedError = error
      } else if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
        capturedError = NSError(domain: "monkeycraft.tailscale", code: http.statusCode, userInfo: [
          NSLocalizedDescriptionKey: "localapi status \(http.statusCode)",
        ])
      }
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
}

#endif
