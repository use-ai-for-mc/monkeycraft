import Foundation

protocol TailscaleDialer: AnyObject {
  func dial(address: String) throws -> Int32
}

enum TailscaleBridgeError: Error, Equatable {
  case notRunning
  case invalidPort
  case unknownNode
  case unknownLease
  case alreadyBridging
  case listenerFailed
  case dialFailed
  case secondClient
}

struct TailscaleBridgeLease: Equatable {
  let leaseId: String
  let url: String
  let port: UInt16
}

protocol LoopbackSocket: AnyObject {
  var fileDescriptor: Int32 { get }
  func write(_ data: Data) throws
  func readAvailable() throws -> Data
  func close()
}

protocol LoopbackListener: AnyObject {
  var port: UInt16 { get }
  func accept() throws -> LoopbackSocket?
  func close()
}

protocol LoopbackListenerFactory {
  func listenLoopback(preferredPort: UInt16) throws -> LoopbackListener
}

final class DarwinLoopbackSocket: LoopbackSocket {
  let fileDescriptor: Int32
  init(fileDescriptor: Int32) { self.fileDescriptor = fileDescriptor }

  func write(_ data: Data) throws {
    try data.withUnsafeBytes { raw in
      var written = 0
      while written < data.count {
        let n = Darwin.write(fileDescriptor, raw.baseAddress!.advanced(by: written), data.count - written)
        if n <= 0 { throw TailscaleBridgeError.listenerFailed }
        written += n
      }
    }
  }

  func readAvailable() throws -> Data {
    var buf = [UInt8](repeating: 0, count: 16 * 1024)
    let n = Darwin.read(fileDescriptor, &buf, buf.count)
    if n < 0 { throw TailscaleBridgeError.listenerFailed }
    if n == 0 { return Data() }
    return Data(buf.prefix(n))
  }

  func close() {
    Darwin.close(fileDescriptor)
  }
}

final class DarwinLoopbackListener: LoopbackListener {
  private let fd: Int32
  let port: UInt16

  init(fd: Int32, port: UInt16) {
    self.fd = fd
    self.port = port
  }

  func accept() throws -> LoopbackSocket? {
    var addr = sockaddr_in()
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    let client = withUnsafeMutablePointer(to: &addr) { pointer -> Int32 in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
        Darwin.accept(fd, sock, &len)
      }
    }
    if client < 0 {
      if errno == EAGAIN || errno == EWOULDBLOCK { return nil }
      throw TailscaleBridgeError.listenerFailed
    }
    let ip = String(cString: inet_ntoa(addr.sin_addr))
    if ip != "127.0.0.1" {
      Darwin.close(client)
      return nil
    }
    return DarwinLoopbackSocket(fileDescriptor: client)
  }

  func close() {
    Darwin.close(fd)
  }
}

struct DarwinLoopbackListenerFactory: LoopbackListenerFactory {
  static let defaultPort: UInt16 = 9600

  func listenLoopback(preferredPort: UInt16) throws -> LoopbackListener {
    if preferredPort != 0, let listener = try? bindLoopback(port: preferredPort) {
      return listener
    }
    return try bindLoopback(port: 0)
  }

  private func bindLoopback(port: UInt16) throws -> LoopbackListener {
    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw TailscaleBridgeError.listenerFailed }
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
    let flags = fcntl(fd, F_GETFL, 0)
    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let bindResult = withUnsafePointer(to: &addr) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
        Darwin.bind(fd, sock, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindResult == 0, Darwin.listen(fd, 1) == 0 else {
      Darwin.close(fd)
      throw TailscaleBridgeError.listenerFailed
    }
    var bound = sockaddr_in()
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
        getsockname(fd, sock, &len)
      }
    }
    guard nameResult == 0 else {
      Darwin.close(fd)
      throw TailscaleBridgeError.listenerFailed
    }
    let boundPort = UInt16(bigEndian: bound.sin_port)
    return DarwinLoopbackListener(fd: fd, port: boundPort)
  }
}

final class TailscaleLoopbackBridge {
  static let idleTimeout: TimeInterval = 30
  static let maxBuffer = 256 * 1024

  private let queue = DispatchQueue(label: "monkeycraft.tailscale.bridge")
  private let listenerFactory: LoopbackListenerFactory
  private let now: () -> Date
  private var listener: LoopbackListener?
  private var localSocket: LoopbackSocket?
  private var remoteFD: Int32 = -1
  private var leaseId: String?
  private var lastActivity = Date()
  private var pumpTimer: DispatchSourceTimer?
  private var copyTask: DispatchWorkItem?

  init(
    listenerFactory: LoopbackListenerFactory = DarwinLoopbackListenerFactory(),
    now: @escaping () -> Date = Date.init
  ) {
    self.listenerFactory = listenerFactory
    self.now = now
  }

  func open(
    nodeId: String,
    port: Int,
    snapshot: TailscaleSnapshot,
    peers: [TailscalePeerInfo],
    dialer: TailscaleDialer
  ) throws -> TailscaleBridgeLease {
    try queue.sync {
      guard snapshot.phase == .running else { throw TailscaleBridgeError.notRunning }
      guard (1...65535).contains(port) else { throw TailscaleBridgeError.invalidPort }
      guard leaseId == nil else { throw TailscaleBridgeError.alreadyBridging }
      guard let peer = peers.first(where: { $0.nodeId == nodeId }) else {
        throw TailscaleBridgeError.unknownNode
      }
      guard let host = peer.dialHost() else {
        throw TailscaleBridgeError.unknownNode
      }
      let fd: Int32
      do {
        fd = try dialer.dial(address: "\(host):\(port)")
      } catch {
        throw error
      }
      let created: LoopbackListener
      do {
        created = try listenerFactory.listenLoopback(preferredPort: UInt16(port))
      } catch {
        Darwin.close(fd)
        throw TailscaleBridgeError.listenerFailed
      }
      listener = created
      remoteFD = fd
      let id = UUID().uuidString
      leaseId = id
      lastActivity = now()
      startPump()
      return TailscaleBridgeLease(
        leaseId: id,
        url: "ws://127.0.0.1:\(created.port)",
        port: created.port
      )
    }
  }

  func close(leaseId requested: String?) throws {
    try queue.sync {
      if let requested {
        if self.leaseId == nil {
          return
        }
        if requested != self.leaseId {
          throw TailscaleBridgeError.unknownLease
        }
      }
      tearDownLocked()
    }
  }

  func closeAll() {
    queue.sync { tearDownLocked() }
  }

  private func startPump() {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now(), repeating: .milliseconds(10))
    timer.setEventHandler { [weak self] in
      self?.pump()
    }
    pumpTimer = timer
    timer.resume()
  }

  private func pump() {
    if now().timeIntervalSince(lastActivity) > Self.idleTimeout {
      tearDownLocked()
      return
    }
    if localSocket == nil {
      let accepted = try? listener?.accept()
      if let socket = accepted ?? nil {
        localSocket = socket
        lastActivity = now()
      }
    }
    guard let local = localSocket, remoteFD >= 0 else { return }
    if let incoming = try? local.readAvailable(), !incoming.isEmpty {
      lastActivity = now()
      incoming.withUnsafeBytes { raw in
        _ = Darwin.write(remoteFD, raw.baseAddress, incoming.count)
      }
    }
    var flags = fcntl(remoteFD, F_GETFL, 0)
    if flags >= 0 {
      _ = fcntl(remoteFD, F_SETFL, flags | O_NONBLOCK)
    }
    var buf = [UInt8](repeating: 0, count: 16 * 1024)
    let n = Darwin.read(remoteFD, &buf, buf.count)
    if n > 0 {
      lastActivity = now()
      try? local.write(Data(buf.prefix(n)))
    } else if n == 0 {
      tearDownLocked()
    }
  }

  private func tearDownLocked() {
    pumpTimer?.cancel()
    pumpTimer = nil
    localSocket?.close()
    localSocket = nil
    listener?.close()
    listener = nil
    if remoteFD >= 0 {
      Darwin.close(remoteFD)
      remoteFD = -1
    }
    leaseId = nil
  }
}

struct TailscalePeerInfo: Equatable {
  let nodeId: String
  let hostName: String
  let online: Bool
  let dnsName: String?
  let tailscaleIPs: [String]

  func asMap() -> [String: Any] {
    var map: [String: Any] = [
      "nodeId": nodeId,
      "hostName": hostName,
      "online": online,
      "tailscaleIPs": tailscaleIPs,
    ]
    if let dnsName { map["dnsName"] = dnsName }
    return map
  }

  func dialHost() -> String? {
    if let ip = tailscaleIPs.first(where: { !$0.contains(":") }) {
      return ip
    }
    if let dnsName, !dnsName.isEmpty {
      return dnsName.hasSuffix(".") ? String(dnsName.dropLast()) : dnsName
    }
    if let ip = tailscaleIPs.first {
      return ip
    }
    return nil
  }
}

enum TailscalePeerParser {
  static func peers(fromStatusJSON data: Data) -> [TailscalePeerInfo] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return []
    }
    return peers(fromJSON: json)
  }

  static func peers(fromJSON json: [String: Any]) -> [TailscalePeerInfo] {
    let selfId = (json["Self"] as? [String: Any])?["ID"] as? String
    guard let peerMap = json["Peer"] as? [String: Any] else { return [] }
    var result: [TailscalePeerInfo] = []
    for (_, value) in peerMap {
      guard let peer = value as? [String: Any] else { continue }
      let nodeId = peer["ID"] as? String ?? ""
      if nodeId.isEmpty || nodeId == selfId { continue }
      let ips = (peer["TailscaleIPs"] as? [Any])?.compactMap { value -> String? in
        let text = "\(value)"
        return text.isEmpty ? nil : text
      } ?? []
      result.append(
        TailscalePeerInfo(
          nodeId: nodeId,
          hostName: peer["HostName"] as? String ?? "",
          online: peer["Online"] as? Bool ?? false,
          dnsName: peer["DNSName"] as? String,
          tailscaleIPs: ips
        )
      )
    }
    result.sort {
      if $0.online != $1.online { return $0.online && !$1.online }
      return $0.hostName.localizedCaseInsensitiveCompare($1.hostName) == .orderedAscending
    }
    return result
  }
}
