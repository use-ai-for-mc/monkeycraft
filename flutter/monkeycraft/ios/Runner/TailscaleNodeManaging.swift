import Foundation

enum TailscalePhase: String {
  case unavailable
  case stopped
  case starting
  case needsLogin
  case needsApproval
  case running
  case stopping
  case failed
}

struct TailscaleSnapshot: Equatable {
  var phase: TailscalePhase
  var errorCode: String?
  var errorMessage: String?
  var authUrlHost: String?
  var nodeId: String?
  var hostName: String?
  var backendState: String?
  var peers: [TailscalePeerInfo] = []

  static let stopped = TailscaleSnapshot(phase: .stopped)

  func asMap() -> [String: Any] {
    var map: [String: Any] = [
      "phase": phase.rawValue,
      "peers": peers.map { $0.asMap() },
    ]
    if let errorCode { map["errorCode"] = errorCode }
    if let errorMessage { map["errorMessage"] = errorMessage }
    if let authUrlHost { map["authUrlHost"] = authUrlHost }
    if let nodeId { map["nodeId"] = nodeId }
    if let hostName { map["hostName"] = hostName }
    if let backendState { map["backendState"] = backendState }
    return map
  }
}

protocol TailscaleNodeBackend: AnyObject, TailscaleDialer {
  func startNode(stateDirectory: URL) throws
  func statusJSON() throws -> Data
  func loginInteractive() throws
  func logout() throws
  func close()
}

protocol TailscaleAuthPresenter {
  func presentAuthURL(_ url: URL, completion: @escaping (Result<Void, Error>) -> Void)
}

enum TailscaleTiming {
  static func defaultRecord(_ stage: String, _ startedAt: DispatchTime) {
    record(stage, startedAt: startedAt)
  }

  static func instant(_ stage: String, phase: TailscalePhase? = nil) {
    append(stage: stage, elapsedMs: 0, phase: phase)
  }

  static func record(_ stage: String, startedAt: DispatchTime, phase: TailscalePhase? = nil) {
    let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds
    append(stage: stage, elapsedMs: elapsed / 1_000_000, phase: phase)
  }

  static func native(stage: UInt8, elapsedMs: Int64, offsetMs: Int64, attempt: UInt64, status: Int) {
    #if MONKEYCRAFT_TAILSCALE_TIMING
    guard (1...4).contains(stage), elapsedMs >= 0, offsetMs >= 0, status >= 0 else { return }
    appendNative(stage: stage, elapsedMs: elapsedMs, offsetMs: offsetMs, attempt: attempt, status: status)
    #endif
  }

  #if MONKEYCRAFT_TAILSCALE_TIMING
  private static let lock = NSLock()
  private static let maximumBytes: UInt64 = 64 * 1024

  private static func append(stage: String, elapsedMs: UInt64, phase: TailscalePhase?) {
    let monotonicMs = DispatchTime.now().uptimeNanoseconds / 1_000_000
    var event: [String: Any] = [
      "stage": stage,
      "monotonicMs": monotonicMs,
      "elapsedMs": elapsedMs,
    ]
    if let phase {
      event["phase"] = phase.rawValue
    }
    guard var data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) else { return }
    data.append(0x0A)
    lock.lock()
    defer { lock.unlock() }
    do {
      let caches = try FileManager.default.url(
        for: .cachesDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      let directory = caches.appendingPathComponent("MonkeyCraftDiagnostics", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent("tailscale-timing.jsonl")
      if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
        let size = attributes[.size] as? NSNumber,
        size.uint64Value >= maximumBytes
      {
        try FileManager.default.removeItem(at: file)
      }
      if !FileManager.default.fileExists(atPath: file.path) {
        FileManager.default.createFile(atPath: file.path, contents: nil)
      }
      let handle = try FileHandle(forWritingTo: file)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
    } catch {}
  }

  private static func appendNative(stage: UInt8, elapsedMs: Int64, offsetMs: Int64, attempt: UInt64, status: Int) {
    let names = ["", "register.do", "register.response", "register.body", "register.decode"]
    let event: [String: Any] = [
      "stage": names[Int(stage)],
      "elapsedMs": elapsedMs,
      "offsetMs": offsetMs,
      "attempt": attempt,
      "status": status,
      "monotonicMs": DispatchTime.now().uptimeNanoseconds / 1_000_000,
    ]
    appendEvent(event)
  }

  private static func appendEvent(_ event: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) else { return }
    data.append(0x0A)
    lock.lock()
    defer { lock.unlock() }
    do {
      let caches = try FileManager.default.url(
        for: .cachesDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      let directory = caches.appendingPathComponent("MonkeyCraftDiagnostics", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent("tailscale-timing.jsonl")
      if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
        let size = attributes[.size] as? NSNumber,
        size.uint64Value >= maximumBytes
      {
        try FileManager.default.removeItem(at: file)
      }
      if !FileManager.default.fileExists(atPath: file.path) {
        FileManager.default.createFile(atPath: file.path, contents: nil)
      }
      let handle = try FileHandle(forWritingTo: file)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
    } catch {}
  }
  #else
  private static func append(stage: String, elapsedMs: UInt64, phase: TailscalePhase?) {}
  #endif
}

enum TailscaleErrorCode: String {
  case notLinked = "not_linked"
  case alreadyStarting = "already_starting"
  case notStarted = "not_started"
  case cancelled = "cancelled"
  case startFailed = "start_failed"
  case statusFailed = "status_failed"
  case loginFailed = "login_failed"
  case logoutFailed = "logout_failed"
  case presentFailed = "present_failed"
}

final class TailscaleNodeManager {
  let queue = DispatchQueue(label: "monkeycraft.tailscale.node")
  private let backendFactory: () -> TailscaleNodeBackend?
  private let presenter: TailscaleAuthPresenter
  private let fileManager: FileManager
  private let timingReporter: (String, DispatchTime) -> Void
  var onSnapshot: ((TailscaleSnapshot) -> Void)?

  private var backend: TailscaleNodeBackend?
  private var pollTimer: DispatchSourceTimer?
  private var lastAuthURL: String?
  private var snapshot = TailscaleSnapshot.stopped
  private var generation = 0

  init(
    backendFactory: @escaping () -> TailscaleNodeBackend?,
    presenter: TailscaleAuthPresenter,
    fileManager: FileManager = .default,
    timingReporter: @escaping (String, DispatchTime) -> Void = TailscaleTiming.defaultRecord
  ) {
    self.backendFactory = backendFactory
    self.presenter = presenter
    self.fileManager = fileManager
    self.timingReporter = timingReporter
  }

  deinit {
    pollTimer?.cancel()
  }

  func currentSnapshot() -> TailscaleSnapshot { snapshot }

  func backendForDial() -> TailscaleNodeBackend? { backend }

  func start() {
    TailscaleTiming.instant("start.entry", phase: snapshot.phase)
    if snapshot.phase == .starting || snapshot.phase == .needsLogin || snapshot.phase == .running
      || snapshot.phase == .needsApproval
    {
      emit(
        TailscaleSnapshot(
          phase: snapshot.phase,
          errorCode: TailscaleErrorCode.alreadyStarting.rawValue,
          errorMessage: "node already starting or running",
          authUrlHost: snapshot.authUrlHost,
          nodeId: snapshot.nodeId,
          hostName: snapshot.hostName,
          backendState: snapshot.backendState,
          peers: snapshot.peers
        )
      )
      return
    }
    discardFailedBackend()
    guard let created = backendFactory() else {
      emit(
        TailscaleSnapshot(
          phase: .unavailable,
          errorCode: TailscaleErrorCode.notLinked.rawValue,
          errorMessage: "libtailscale is not linked"
        )
      )
      return
    }
    generation += 1
    lastAuthURL = nil
    backend = created
    emit(TailscaleSnapshot(phase: .starting))
    let startedAt = DispatchTime.now()
    do {
      try created.startNode(stateDirectory: try stateDirectory())
      timingReporter("start.return", startedAt)
      refreshStatus()
      startPolling()
    } catch {
      timingReporter("start.failed", startedAt)
      emit(
        TailscaleSnapshot(
          phase: .failed,
          errorCode: TailscaleErrorCode.startFailed.rawValue,
          errorMessage: Self.redact(error.localizedDescription)
        )
      )
      created.close()
      backend = nil
    }
  }

  func loginInteractive() {
    TailscaleTiming.instant("login.entry", phase: snapshot.phase)
    guard let backend else {
      emit(
        TailscaleSnapshot(
          phase: snapshot.phase == .unavailable ? .unavailable : .failed,
          errorCode: TailscaleErrorCode.notStarted.rawValue,
          errorMessage: "node is not started"
        )
      )
      return
    }
    let startedAt = DispatchTime.now()
    do {
      lastAuthURL = nil
      try backend.loginInteractive()
      timingReporter("login.return", startedAt)
      refreshStatus()
    } catch {
      timingReporter("login.failed", startedAt)
      emit(
        TailscaleSnapshot(
          phase: .failed,
          errorCode: TailscaleErrorCode.loginFailed.rawValue,
          errorMessage: Self.redact(error.localizedDescription),
          nodeId: snapshot.nodeId,
          hostName: snapshot.hostName,
          backendState: snapshot.backendState
        )
      )
    }
  }

  func cancel() {
    generation += 1
    stopPolling()
    backend?.close()
    backend = nil
    lastAuthURL = nil
    emit(
      TailscaleSnapshot(
        phase: .stopped,
        errorCode: TailscaleErrorCode.cancelled.rawValue,
        errorMessage: "login cancelled"
      )
    )
  }

  func logout() {
    generation += 1
    stopPolling()
    if let backend {
      do {
        try backend.logout()
      } catch {
        emit(
          TailscaleSnapshot(
            phase: .failed,
            errorCode: TailscaleErrorCode.logoutFailed.rawValue,
            errorMessage: Self.redact(error.localizedDescription)
          )
        )
      }
      backend.close()
    }
    self.backend = nil
    lastAuthURL = nil
    if let dir = try? stateDirectory() {
      try? fileManager.removeItem(at: dir)
    }
    emit(TailscaleSnapshot.stopped)
  }

  func stop() {
    generation += 1
    stopPolling()
    backend?.close()
    backend = nil
    lastAuthURL = nil
    emit(TailscaleSnapshot.stopped)
  }

  func refreshStatus() {
    guard let backend else { return }
    let captured = generation
    let startedAt = DispatchTime.now()
    do {
      let data = try backend.statusJSON()
      timingReporter("statusJSON", startedAt)
      guard captured == generation else { return }
      applyStatusJSON(data)
    } catch {
      timingReporter("statusJSON.failed", startedAt)
      guard captured == generation else { return }
      emit(
        TailscaleSnapshot(
          phase: snapshot.phase == .running ? .running : .failed,
          errorCode: TailscaleErrorCode.statusFailed.rawValue,
          errorMessage: Self.redact(error.localizedDescription),
          authUrlHost: snapshot.authUrlHost,
          nodeId: snapshot.nodeId,
          hostName: snapshot.hostName,
          backendState: snapshot.backendState
        )
      )
    }
  }

  func applyStatusJSON(_ data: Data) {
    guard
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      emit(
        TailscaleSnapshot(
          phase: .failed,
          errorCode: TailscaleErrorCode.statusFailed.rawValue,
          errorMessage: "status json was not an object"
        )
      )
      return
    }
    let backendState = (json["BackendState"] as? String) ?? ""
    let authURL = json["AuthURL"] as? String
    let selfStatus = json["Self"] as? [String: Any]
    let nodeId = selfStatus?["ID"] as? String
    let hostName = selfStatus?["HostName"] as? String
    let health = json["Health"] as? [Any]

    var next = TailscaleSnapshot(
      phase: phase(forBackendState: backendState, health: health),
      nodeId: nodeId,
      hostName: hostName,
      backendState: backendState,
      peers: TailscalePeerParser.peers(fromJSON: json)
    )

    if let authURL, !authURL.isEmpty, let url = URL(string: authURL) {
      next.authUrlHost = url.host
      if lastAuthURL != authURL {
        lastAuthURL = authURL
        TailscaleTiming.instant("authURL.first", phase: next.phase)
        let startedAt = DispatchTime.now()
        let capturedGeneration = generation
        presenter.presentAuthURL(url) { [weak self] result in
          self?.queue.async {
            guard let self, capturedGeneration == self.generation, self.lastAuthURL == authURL else { return }
            switch result {
            case .success:
              self.timingReporter("presentAuthURL", startedAt)
            case .failure(let error):
              self.timingReporter("presentAuthURL.failed", startedAt)
              self.emit(
                TailscaleSnapshot(
                  phase: .failed,
                  errorCode: TailscaleErrorCode.presentFailed.rawValue,
                  errorMessage: Self.redact(error.localizedDescription),
                  authUrlHost: self.snapshot.authUrlHost,
                  nodeId: self.snapshot.nodeId,
                  hostName: self.snapshot.hostName,
                  backendState: self.snapshot.backendState,
                  peers: self.snapshot.peers
                )
              )
            }
          }
        }
      }
    }
    emit(next)
  }

  static func redact(_ message: String) -> String {
    var output = message
    if let regex = try? NSRegularExpression(
      pattern: #"https?://[^\s\"']+"#,
      options: [.caseInsensitive]
    ) {
      output = regex.stringByReplacingMatches(
        in: output,
        range: NSRange(output.startIndex..<output.endIndex, in: output),
        withTemplate: "<redacted-url>"
      )
    }
    if let regex = try? NSRegularExpression(
      pattern: #"tskey-[A-Za-z0-9_-]+"#,
      options: []
    ) {
      output = regex.stringByReplacingMatches(
        in: output,
        range: NSRange(output.startIndex..<output.endIndex, in: output),
        withTemplate: "<redacted-key>"
      )
    }
    return output
  }

  static func hostFromAuthURL(_ urlString: String) -> String? {
    URL(string: urlString)?.host
  }

  private func phase(forBackendState state: String, health: [Any]?) -> TailscalePhase {
    switch state {
    case "NeedsLogin":
      return .needsLogin
    case "NeedsMachineAuth":
      return .needsApproval
    case "Running":
      return .running
    case "Starting", "NoState":
      return .starting
    case "Stopped":
      return .stopped
    default:
      if let health, !health.isEmpty {
        return .failed
      }
      return .starting
    }
  }

  private func emit(_ snapshot: TailscaleSnapshot) {
    self.snapshot = snapshot
    TailscaleTiming.instant("phase", phase: snapshot.phase)
    onSnapshot?(snapshot)
  }

  private func startPolling() {
    stopPolling()
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
    timer.setEventHandler { [weak self] in
      self?.refreshStatus()
    }
    pollTimer = timer
    timer.resume()
  }

  private func stopPolling() {
    pollTimer?.cancel()
    pollTimer = nil
  }

  private func discardFailedBackend() {
    guard snapshot.phase == .failed else { return }
    stopPolling()
    backend?.close()
    backend = nil
    lastAuthURL = nil
  }

  private func stateDirectory() throws -> URL {
    let root = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let dir = root.appendingPathComponent("MonkeyCraftTailscale", isDirectory: true)
    try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var mutable = dir
    try mutable.setResourceValues(values)
    return dir
  }
}
