import Flutter
import UIKit
import VideoToolbox
import CoreMedia
import CoreVideo
import UserNotifications
import Darwin

final class H264DecoderPlugin: NSObject, FlutterPlugin {
  private let textureRegistry: FlutterTextureRegistry
  private var decoder: H264Decoder?

  init(textureRegistry: FlutterTextureRegistry) {
    self.textureRegistry = textureRegistry
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "monkeycraft/h264_decoder", binaryMessenger: registrar.messenger())
    let instance = H264DecoderPlugin(textureRegistry: registrar.textures())
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createDecoder":
      let args = (call.arguments as? [String: Any]) ?? [:]
      let fps = args["fps"] as? Int ?? 20
      decoder?.dispose(textureRegistry: textureRegistry)
      decoder = nil
      let texture = H264Texture()
      let textureId = textureRegistry.register(texture)
      decoder = H264Decoder(texture: texture, textureId: textureId, fps: fps, textureRegistry: textureRegistry)
      result(["textureId": textureId])
    case "pushAccessUnit":
      guard let decoder else {
        result(FlutterError(code: "no_decoder", message: "Decoder not initialized", details: nil))
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let data = args["bytes"] as? FlutterStandardTypedData
      else {
        result(FlutterError(code: "bad_args", message: "Missing bytes", details: nil))
        return
      }
      decoder.push(accessUnit: data.data, textureRegistry: textureRegistry)
      result(nil)
    case "resetDecoder":
      decoder?.reset()
      result(nil)
    case "getStats":
      result(decoder?.stats() ?? [:])
    case "disposeDecoder":
      decoder?.dispose(textureRegistry: textureRegistry)
      decoder = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

final class NotificationsPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "monkeycraft/notifications", binaryMessenger: registrar.messenger())
    let instance = NotificationsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermission":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        result(granted)
      }
    case "scheduleTimed":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "Missing args", details: nil))
        return
      }
      guard
        let id = args["id"] as? Int,
        let fireAt = args["fireAtEpochMs"] as? Int,
        let title = args["title"] as? String,
        let body = args["body"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "Missing required fields", details: nil))
        return
      }

      let soundEnabled = args["sound"] as? Bool ?? true
      let identifier = "timed_\(id)"

      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      if soundEnabled {
        content.sound = .default
      }

      let seconds = max(1.0, Double(fireAt) / 1000.0 - Date().timeIntervalSince1970)
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)

      let center = UNUserNotificationCenter.current()
      center.removePendingNotificationRequests(withIdentifiers: [identifier])
      center.removeDeliveredNotifications(withIdentifiers: [identifier])
      let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
      center.add(request) { error in
        if let error {
          result(FlutterError(code: "schedule_failed", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
    case "cancelTimed":
      guard let args = call.arguments as? [String: Any], let id = args["id"] as? Int else {
        result(FlutterError(code: "bad_args", message: "Missing id", details: nil))
        return
      }
      let identifier = "timed_\(id)"
      let center = UNUserNotificationCenter.current()
      center.removePendingNotificationRequests(withIdentifiers: [identifier])
      center.removeDeliveredNotifications(withIdentifiers: [identifier])
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

final class H264Texture: NSObject, FlutterTexture {
  private let lock = NSLock()
  private var pixelBuffer: CVPixelBuffer?

  func set(pixelBuffer: CVPixelBuffer?) {
    lock.lock()
    self.pixelBuffer = pixelBuffer
    lock.unlock()
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    guard let pixelBuffer else {
      lock.unlock()
      return nil
    }
    lock.unlock()
    return Unmanaged.passRetained(pixelBuffer)
  }
}

final class H264Decoder {
  private static let queueKey = DispatchSpecificKey<UInt8>()

  private let texture: H264Texture
  private let textureId: Int64
  private weak var textureRegistry: FlutterTextureRegistry?
  private var fps: Int
  private var frameIndex: Int64 = 0
  private var inputAccessUnits: Int64 = 0
  private var decodedFrames: Int64 = 0
  private var droppedAccessUnits: Int64 = 0
  private let decodeQueue = DispatchQueue(label: "monkeycraft.h264.decode")
  private var decoding: Bool = false
  private var pendingAccessUnit: Data?
  private var disposed: Bool = false
  private var lastWidth: Int = 0
  private var lastHeight: Int = 0
  private var lastPixelFormat: Int = 0

  private var sps: Data?
  private var pps: Data?
  private var formatDescription: CMVideoFormatDescription?
  private var session: VTDecompressionSession?

  init(texture: H264Texture, textureId: Int64, fps: Int, textureRegistry: FlutterTextureRegistry) {
    self.texture = texture
    self.textureId = textureId
    self.fps = max(1, fps)
    self.textureRegistry = textureRegistry
    decodeQueue.setSpecific(key: H264Decoder.queueKey, value: 1)
  }

  func reset() {
    syncOnDecodeQueue {
      teardownSession()
      sps = nil
      pps = nil
      formatDescription = nil
      frameIndex = 0
      inputAccessUnits = 0
      decodedFrames = 0
      droppedAccessUnits = 0
      pendingAccessUnit = nil
      decoding = false
      disposed = false
    }
  }

  func dispose(textureRegistry: FlutterTextureRegistry) {
    syncOnDecodeQueue {
      disposed = true
      pendingAccessUnit = nil
      decoding = false
      teardownSession()
      self.textureRegistry = nil
    }
    texture.set(pixelBuffer: nil)
    textureRegistry.unregisterTexture(textureId)
  }

  func push(accessUnit: Data, textureRegistry: FlutterTextureRegistry) {
    if disposed { return }
    self.textureRegistry = textureRegistry
    inputAccessUnits += 1
    decodeQueue.async {
      if self.disposed { return }
      if self.decoding {
        if self.pendingAccessUnit != nil {
          self.droppedAccessUnits += 1
        }
        self.pendingAccessUnit = accessUnit
        return
      }
      self.pendingAccessUnit = accessUnit
      self.decoding = true
      self.decodeLoop()
    }
  }

  private func decodeLoop() {
    while true {
      guard let accessUnit = pendingAccessUnit else { break }
      pendingAccessUnit = nil
      decodeOne(accessUnit: accessUnit)
    }
    decoding = false
  }

  private func decodeOne(accessUnit: Data) {
    if disposed { return }
    let nalUnits = AnnexB.parse(accessUnit: accessUnit)
    if nalUnits.isEmpty { return }

    var hasSlice = false
    var sampleNals: [Data] = []
    for nal in nalUnits {
      let type = AnnexB.nalType(nal)
      if type == 7 { sps = nal }
      if type == 8 { pps = nal }
      if type == 1 || type == 5 {
        hasSlice = true
        sampleNals.append(nal)
      } else if type == 6 || type == 9 {
        sampleNals.append(nal)
      }
    }

    if session == nil, let sps, let pps {
      if createSessionIfPossible(sps: sps, pps: pps) == false {
        return
      }
    }

    guard hasSlice, let session, let formatDescription else { return }

    let avcc = AnnexB.toAvcc(accessUnit: sampleNals)
    var blockBuffer: CMBlockBuffer?
    let status1 = CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault,
      memoryBlock: nil,
      blockLength: avcc.count,
      blockAllocator: kCFAllocatorDefault,
      customBlockSource: nil,
      offsetToData: 0,
      dataLength: avcc.count,
      flags: 0,
      blockBufferOut: &blockBuffer
    )
    if status1 != kCMBlockBufferNoErr || blockBuffer == nil { return }

    avcc.withUnsafeBytes { raw in
      if let base = raw.baseAddress {
        CMBlockBufferReplaceDataBytes(
          with: base,
          blockBuffer: blockBuffer!,
          offsetIntoDestination: 0,
          dataLength: avcc.count
        )
      }
    }

    var timing = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: CMTimeScale(fps)),
      presentationTimeStamp: CMTime(value: frameIndex, timescale: CMTimeScale(fps)),
      decodeTimeStamp: CMTime.invalid
    )
    frameIndex += 1

    var sampleBuffer: CMSampleBuffer?
    let status2 = CMSampleBufferCreateReady(
      allocator: kCFAllocatorDefault,
      dataBuffer: blockBuffer,
      formatDescription: formatDescription,
      sampleCount: 1,
      sampleTimingEntryCount: 1,
      sampleTimingArray: &timing,
      sampleSizeEntryCount: 0,
      sampleSizeArray: nil,
      sampleBufferOut: &sampleBuffer
    )
    if status2 != noErr || sampleBuffer == nil { return }

    var flags: VTDecodeFrameFlags = [
      VTDecodeFrameFlags._EnableAsynchronousDecompression,
      VTDecodeFrameFlags._1xRealTimePlayback
    ]
    var infoFlags = VTDecodeInfoFlags()
    let status3 = VTDecompressionSessionDecodeFrame(
      session,
      sampleBuffer: sampleBuffer!,
      flags: flags,
      frameRefcon: nil,
      infoFlagsOut: &infoFlags
    )
    if status3 != noErr {
      return
    }
  }

  private func createSessionIfPossible(sps: Data, pps: Data) -> Bool {
    var desc: CMFormatDescription?
    let status: OSStatus = sps.withUnsafeBytes { spsRaw in
      pps.withUnsafeBytes { ppsRaw in
        guard
          let spsPtr = spsRaw.bindMemory(to: UInt8.self).baseAddress,
          let ppsPtr = ppsRaw.bindMemory(to: UInt8.self).baseAddress
        else { return -1 }
        var pointers: [UnsafePointer<UInt8>] = [spsPtr, ppsPtr]
        var sizes: [Int] = [sps.count, pps.count]
        return CMVideoFormatDescriptionCreateFromH264ParameterSets(
          allocator: kCFAllocatorDefault,
          parameterSetCount: 2,
          parameterSetPointers: &pointers,
          parameterSetSizes: &sizes,
          nalUnitHeaderLength: 4,
          formatDescriptionOut: &desc
        )
      }
    }
    if status != noErr || desc == nil { return false }

    formatDescription = desc as! CMVideoFormatDescription

    var callbackRecord = VTDecompressionOutputCallbackRecord(
      decompressionOutputCallback: H264Decoder.outputCallback,
      decompressionOutputRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    )

    let attrs: [NSString: Any] = [
      kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
      kCVPixelBufferIOSurfacePropertiesKey: [:],
      kCVPixelBufferMetalCompatibilityKey: true
    ]

    var created: VTDecompressionSession?
    let status2 = VTDecompressionSessionCreate(
      allocator: kCFAllocatorDefault,
      formatDescription: formatDescription!,
      decoderSpecification: nil,
      imageBufferAttributes: attrs as CFDictionary,
      outputCallback: &callbackRecord,
      decompressionSessionOut: &created
    )
    if status2 != noErr || created == nil {
      formatDescription = nil
      return false
    }

    session = created
    VTSessionSetProperty(session!, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
    return true
  }

  private func teardownSession() {
    if let session {
      VTDecompressionSessionInvalidate(session)
      self.session = nil
    }
  }

  private static let outputCallback: VTDecompressionOutputCallback = { refCon, _, status, _, imageBuffer, _, _ in
    guard status == noErr, let refCon, let imageBuffer else { return }
    let decoder = Unmanaged<H264Decoder>.fromOpaque(refCon).takeUnretainedValue()
    if decoder.disposed { return }
    decoder.texture.set(pixelBuffer: imageBuffer)
    decoder.decodedFrames += 1
    decoder.lastWidth = CVPixelBufferGetWidth(imageBuffer)
    decoder.lastHeight = CVPixelBufferGetHeight(imageBuffer)
    decoder.lastPixelFormat = Int(CVPixelBufferGetPixelFormatType(imageBuffer))
    DispatchQueue.main.async {
      if decoder.disposed { return }
      decoder.textureRegistry?.textureFrameAvailable(decoder.textureId)
    }
  }

  func stats() -> [String: Any] {
    return [
      "fps": fps,
      "inputAccessUnits": inputAccessUnits,
      "decodedFrames": decodedFrames,
      "droppedAccessUnits": droppedAccessUnits,
      "decoding": decoding,
      "width": lastWidth,
      "height": lastHeight,
      "pixelFormat": lastPixelFormat
    ]
  }

  private func syncOnDecodeQueue(_ block: () -> Void) {
    if DispatchQueue.getSpecific(key: H264Decoder.queueKey) != nil {
      block()
    } else {
      decodeQueue.sync(execute: block)
    }
  }
}

enum AnnexB {
  static func nalType(_ nal: Data) -> UInt8 {
    guard let first = nal.first else { return 0 }
    return first & 0x1F
  }

  static func parse(accessUnit: Data) -> [Data] {
    let bytes = [UInt8](accessUnit)
    var nalStarts: [Int] = []

    var i = 0
    while i + 3 < bytes.count {
      if bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1 {
        nalStarts.append(i)
        i += 3
        continue
      }
      if i + 4 < bytes.count && bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 0 && bytes[i + 3] == 1 {
        nalStarts.append(i)
        i += 4
        continue
      }
      i += 1
    }

    if nalStarts.isEmpty { return [] }

    var nals: [Data] = []
    for index in 0..<nalStarts.count {
      let start = nalStarts[index]
      let nextStart = (index + 1 < nalStarts.count) ? nalStarts[index + 1] : bytes.count
      var headerLen = 3
      if start + 3 < bytes.count && bytes[start] == 0 && bytes[start + 1] == 0 && bytes[start + 2] == 0 && bytes[start + 3] == 1 {
        headerLen = 4
      }
      let nalStart = start + headerLen
      if nalStart >= nextStart { continue }
      let nal = Data(bytes[nalStart..<nextStart])
      if !nal.isEmpty { nals.append(nal) }
    }
    return nals
  }

  static func toAvcc(accessUnit: [Data]) -> Data {
    var out = Data()
    for nal in accessUnit {
      var len = UInt32(nal.count).bigEndian
      withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
      out.append(nal)
    }
    return out
  }
}
