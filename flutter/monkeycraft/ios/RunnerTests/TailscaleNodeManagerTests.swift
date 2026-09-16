import XCTest
@testable import Runner

final class FakeBackend: TailscaleNodeBackend {
  var startCount = 0
  var loginCount = 0
  var logoutCount = 0
  var closeCount = 0
  var statusPayloads: [Data]
  var startError: Error?
  var loginError: Error?
  var startedDirectory: URL?
  private var lastPayload: Data?

  init(statusPayloads: [Data]) {
    self.statusPayloads = statusPayloads
  }

  func startNode(stateDirectory: URL) throws {
    startCount += 1
    startedDirectory = stateDirectory
    if let startError { throw startError }
  }

  func statusJSON() throws -> Data {
    if statusPayloads.isEmpty {
      if let lastPayload { return lastPayload }
      throw NSError(domain: "test", code: 1)
    }
    let payload = statusPayloads.removeFirst()
    lastPayload = payload
    return payload
  }

  func loginInteractive() throws {
    loginCount += 1
    if let loginError { throw loginError }
  }

  func logout() throws {
    logoutCount += 1
  }

  func close() {
    closeCount += 1
  }

  func dial(address: String) throws -> Int32 {
    throw NSError(domain: "test", code: 2)
  }
}

final class FakePresenter: TailscaleAuthPresenter {
  var urls: [URL] = []
  func presentAuthURL(_ url: URL) throws {
    urls.append(url)
  }
}

final class TailscaleNodeManagerTests: XCTestCase {
  func statusJSON(state: String, authURL: String = "", id: String = "n123") -> Data {
    let json: [String: Any] = [
      "BackendState": state,
      "AuthURL": authURL,
      "Self": ["ID": id, "HostName": "monkeycraft-ios"],
    ]
    return try! JSONSerialization.data(withJSONObject: json)
  }

  func makeManager(
    backend: FakeBackend,
    presenter: FakePresenter = FakePresenter()
  ) -> (TailscaleNodeManager, FakePresenter) {
    let manager = TailscaleNodeManager(
      backendFactory: { backend },
      presenter: presenter
    )
    return (manager, presenter)
  }

  func testIdleToNeedsLoginToRunning() {
    let backend = FakeBackend(statusPayloads: [
      statusJSON(state: "NeedsLogin", authURL: "https://login.tailscale.com/a/abc"),
      statusJSON(state: "Running"),
    ])
    let (manager, presenter) = makeManager(backend: backend)
    var phases: [String] = []
    manager.onSnapshot = { phases.append($0.phase.rawValue) }

    manager.start()
    XCTAssertEqual(manager.currentSnapshot().phase, .needsLogin)
    XCTAssertEqual(manager.currentSnapshot().authUrlHost, "login.tailscale.com")
    XCTAssertEqual(presenter.urls.count, 1)
    XCTAssertEqual(presenter.urls.first?.host, "login.tailscale.com")

    manager.refreshStatus()
    XCTAssertEqual(manager.currentSnapshot().phase, .running)
    XCTAssertEqual(manager.currentSnapshot().nodeId, "n123")
    XCTAssertEqual(phases, ["starting", "needsLogin", "running"])
  }

  func testRepeatedStartDoesNotCreateSecondBackend() {
    let backend = FakeBackend(statusPayloads: [statusJSON(state: "Starting")])
    let (manager, _) = makeManager(backend: backend)
    manager.start()
    manager.start()
    XCTAssertEqual(backend.startCount, 1)
    XCTAssertEqual(manager.currentSnapshot().errorCode, "already_starting")
  }

  func testCancelWhileStartingStopsAndCloses() {
    let backend = FakeBackend(statusPayloads: [statusJSON(state: "Starting")])
    let (manager, _) = makeManager(backend: backend)
    manager.start()
    manager.cancel()
    XCTAssertEqual(backend.closeCount, 1)
    XCTAssertEqual(manager.currentSnapshot().phase, .stopped)
    XCTAssertEqual(manager.currentSnapshot().errorCode, "cancelled")
  }

  func testExpiredDeviceNeedsApproval() {
    let backend = FakeBackend(statusPayloads: [statusJSON(state: "NeedsMachineAuth")])
    let (manager, _) = makeManager(backend: backend)
    manager.start()
    XCTAssertEqual(manager.currentSnapshot().phase, .needsApproval)
  }

  func testRedactsAuthURLAndKeys() {
    let redacted = TailscaleNodeManager.redact(
      "open https://login.tailscale.com/a/secret tskey-auth-ABCDEFG leftover"
    )
    XCTAssertFalse(redacted.contains("login.tailscale.com/a/secret"))
    XCTAssertFalse(redacted.contains("tskey-auth-ABCDEFG"))
    XCTAssertTrue(redacted.contains("<redacted-url>"))
    XCTAssertTrue(redacted.contains("<redacted-key>"))
  }

  func testLogoutClosesBackend() {
    let backend = FakeBackend(statusPayloads: [statusJSON(state: "Running")])
    let (manager, _) = makeManager(backend: backend)
    manager.start()
    manager.logout()
    XCTAssertEqual(backend.logoutCount, 1)
    XCTAssertEqual(backend.closeCount, 1)
    XCTAssertEqual(manager.currentSnapshot().phase, .stopped)
  }

  func testMissingBackendIsUnavailable() {
    let manager = TailscaleNodeManager(backendFactory: { nil }, presenter: FakePresenter())
    manager.start()
    XCTAssertEqual(manager.currentSnapshot().phase, .unavailable)
    XCTAssertEqual(manager.currentSnapshot().errorCode, "not_linked")
  }

  func testParsesPeersAndSkipsSelf() {
    let json: [String: Any] = [
      "BackendState": "Running",
      "Self": ["ID": "self1", "HostName": "phone"],
      "Peer": [
        "a": ["ID": "self1", "HostName": "phone", "Online": true],
        "b": [
          "ID": "pc1",
          "HostName": "desk",
          "Online": true,
          "DNSName": "desk.ts.net.",
          "TailscaleIPs": ["100.64.1.2", "fd7a:115c:a1e0::1"],
        ],
        "c": ["ID": "pc2", "HostName": "laptop", "Online": false],
      ],
    ]
    let data = try! JSONSerialization.data(withJSONObject: json)
    let backend = FakeBackend(statusPayloads: [data])
    let (manager, _) = makeManager(backend: backend)
    manager.start()
    XCTAssertEqual(manager.currentSnapshot().peers.map(\.nodeId), ["pc1", "pc2"])
    XCTAssertEqual(manager.currentSnapshot().peers.first?.online, true)
    XCTAssertEqual(manager.currentSnapshot().peers.first?.dialHost(), "100.64.1.2")
  }
}

final class InMemorySocket: LoopbackSocket {
  var fileDescriptor: Int32 = 1
  var written = Data()
  var inbound = Data()
  var closed = false

  func write(_ data: Data) throws {
    written.append(data)
  }

  func readAvailable() throws -> Data {
    let out = inbound
    inbound = Data()
    return out
  }

  func close() { closed = true }
}

final class InMemoryListener: LoopbackListener {
  let port: UInt16 = 4242
  var pending: LoopbackSocket?
  var closed = false

  func accept() throws -> LoopbackSocket? {
    let next = pending
    pending = nil
    return next
  }

  func close() { closed = true }
}

final class InMemoryListenerFactory: LoopbackListenerFactory {
  let listener = InMemoryListener()
  var requestedPorts: [UInt16] = []
  func listenLoopback(preferredPort: UInt16) throws -> LoopbackListener {
    requestedPorts.append(preferredPort)
    return listener
  }
}

final class RecordingDialer: TailscaleDialer {
  var addresses: [String] = []
  var fd: Int32 = 99
  func dial(address: String) throws -> Int32 {
    addresses.append(address)
    return fd
  }
}

final class TailscaleLoopbackBridgeTests: XCTestCase {
  let running = TailscaleSnapshot(phase: .running, peers: [
    TailscalePeerInfo(nodeId: "pc1", hostName: "desk", online: true, dnsName: "desk.ts.net.", tailscaleIPs: ["100.64.1.2"]),
  ])

  func testRejectsWhenNotRunning() {
    let bridge = TailscaleLoopbackBridge(listenerFactory: InMemoryListenerFactory())
    XCTAssertThrowsError(
      try bridge.open(
        nodeId: "pc1",
        port: 9600,
        snapshot: TailscaleSnapshot.stopped,
        peers: running.peers,
        dialer: RecordingDialer()
      )
    )
  }

  func testRejectsUnknownNodeAndBadPort() {
    let bridge = TailscaleLoopbackBridge(listenerFactory: InMemoryListenerFactory())
    XCTAssertThrowsError(
      try bridge.open(nodeId: "nope", port: 9600, snapshot: running, peers: running.peers, dialer: RecordingDialer())
    )
    XCTAssertThrowsError(
      try bridge.open(nodeId: "pc1", port: 0, snapshot: running, peers: running.peers, dialer: RecordingDialer())
    )
  }

  func testOpensLoopbackUrlAndDialsStableId() throws {
    let factory = InMemoryListenerFactory()
    let dialer = RecordingDialer()
    let bridge = TailscaleLoopbackBridge(listenerFactory: factory)
    let lease = try bridge.open(
      nodeId: "pc1",
      port: 9600,
      snapshot: running,
      peers: running.peers,
      dialer: dialer
    )
    XCTAssertEqual(lease.url, "ws://127.0.0.1:4242")
    XCTAssertEqual(dialer.addresses, ["100.64.1.2:9600"])
    XCTAssertEqual(factory.requestedPorts, [9600])
    XCTAssertFalse(lease.leaseId.isEmpty)
    try bridge.close(leaseId: lease.leaseId)
    XCTAssertTrue(factory.listener.closed)
  }

  func testUnknownLeaseIsRejected() throws {
    let bridge = TailscaleLoopbackBridge(listenerFactory: InMemoryListenerFactory())
    let lease = try bridge.open(
      nodeId: "pc1",
      port: 9600,
      snapshot: running,
      peers: running.peers,
      dialer: RecordingDialer()
    )
    XCTAssertThrowsError(try bridge.close(leaseId: "other"))
    try bridge.close(leaseId: lease.leaseId)
    try bridge.close(leaseId: lease.leaseId)
  }

  func testDarwinFactoryFallsBackWhenPreferredPortIsBusy() throws {
    let occupied = DarwinLoopbackListenerFactory()
    let first = try occupied.listenLoopback(preferredPort: 9600)
    defer { first.close() }
    let second = try DarwinLoopbackListenerFactory().listenLoopback(preferredPort: 9600)
    defer { second.close() }
    if first.port == 9600 {
      XCTAssertNotEqual(second.port, 9600)
    }
    XCTAssertNotEqual(second.port, 0)
  }
}
