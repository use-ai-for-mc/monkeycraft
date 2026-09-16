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
  func presentAuthURL(_ url: URL) throws
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
  var onSnapshot: ((TailscaleSnapshot) -> Void)?

  private var backend: TailscaleNodeBackend?
  private var pollTimer: DispatchSourceTimer?
  private var lastAuthURL: String?
  private var snapshot = TailscaleSnapshot.stopped
  private var generation = 0

  init(
    backendFactory: @escaping () -> TailscaleNodeBackend?,
    presenter: TailscaleAuthPresenter,
    fileManager: FileManager = .default
  ) {
    self.backendFactory = backendFactory
    self.presenter = presenter
    self.fileManager = fileManager
  }

  deinit {
    pollTimer?.cancel()
  }

  func currentSnapshot() -> TailscaleSnapshot { snapshot }

  func backendForDial() -> TailscaleNodeBackend? { backend }

  func start() {
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
          backendState: snapshot.backendState
        )
      )
      return
    }
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
    do {
      try created.startNode(stateDirectory: try stateDirectory())
      refreshStatus()
      startPolling()
    } catch {
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
    do {
      try backend.loginInteractive()
      refreshStatus()
    } catch {
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
    do {
      let data = try backend.statusJSON()
      guard captured == generation else { return }
      applyStatusJSON(data)
    } catch {
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
        do {
          try presenter.presentAuthURL(url)
        } catch {
          next.phase = .failed
          next.errorCode = TailscaleErrorCode.presentFailed.rawValue
          next.errorMessage = Self.redact(error.localizedDescription)
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
