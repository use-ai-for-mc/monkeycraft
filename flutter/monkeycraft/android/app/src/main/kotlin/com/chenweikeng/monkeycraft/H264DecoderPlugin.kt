package com.chenweikeng.monkeycraft

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer

class H264DecoderPlugin(
    private val textureRegistry: TextureRegistry,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "monkeycraft/h264_decoder")
    private var decoder: DecoderSession? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        decoder?.dispose()
        decoder = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createDecoder" -> {
                val fps = (call.arguments as? Map<*, *>)?.get("fps") as? Int ?: 20
                decoder?.dispose()
                decoder = DecoderSession(textureRegistry, fps)
                result.success(mapOf("textureId" to decoder!!.textureId))
            }
            "pushAccessUnit" -> {
                val bytes = (call.arguments as? Map<*, *>)?.get("bytes") as? ByteArray
                if (bytes != null) {
                    decoder?.pushAccessUnit(bytes)
                }
                result.success(null)
            }
            "resetDecoder" -> {
                decoder?.reset()
                result.success(null)
            }
            "getStats" -> {
                result.success(decoder?.stats() ?: emptyMap<String, Any>())
            }
            "disposeDecoder" -> {
                decoder?.dispose()
                decoder = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private class DecoderSession(
        private val textureRegistry: TextureRegistry,
        private val fps: Int
    ) {
        private val thread = HandlerThread("H264Decoder")
        private val handler: Handler

        private val entry: TextureRegistry.SurfaceTextureEntry = textureRegistry.createSurfaceTexture()
        val textureId: Long = entry.id()

        private var surface: Surface? = null
        private var codec: MediaCodec? = null

        private var sps: ByteArray? = null
        private var pps: ByteArray? = null
        private var width: Int = 0
        private var height: Int = 0

        private var frameIndex: Long = 0
        private var inputAccessUnits: Long = 0
        private var decodedFrames: Long = 0
        private var droppedAccessUnits: Long = 0
        private var decoding: Boolean = false

        init {
            thread.start()
            handler = Handler(thread.looper)
        }

        fun pushAccessUnit(bytes: ByteArray) {
            handler.post {
                inputAccessUnits += 1
                try {
                    val nals = AnnexB.parseAccessUnit(bytes)
                    for (nal in nals) {
                        val type = nal[0].toInt() and 0x1F
                        if (type == 7) {
                            sps = nal
                        } else if (type == 8) {
                            pps = nal
                        }
                    }
                    ensureCodecIfPossible()
                    val c = codec
                    if (c == null) {
                        droppedAccessUnits += 1
                        return@post
                    }
                    decode(bytes, c)
                } catch (_: Exception) {
                    droppedAccessUnits += 1
                }
            }
        }

        fun reset() {
            handler.post {
                stopCodec()
                frameIndex = 0
                inputAccessUnits = 0
                decodedFrames = 0
                droppedAccessUnits = 0
                decoding = false
            }
        }

        fun stats(): Map<String, Any> {
            return mapOf(
                "fps" to fps,
                "inputAccessUnits" to inputAccessUnits,
                "decodedFrames" to decodedFrames,
                "droppedAccessUnits" to droppedAccessUnits,
                "decoding" to decoding,
                "width" to width,
                "height" to height,
                "pixelFormat" to 0
            )
        }

        fun dispose() {
            handler.post {
                stopCodec()
                surface?.release()
                surface = null
            }
            // entry.release() must be called on the main/UI thread
            Handler(Looper.getMainLooper()).post {
                entry.release()
            }
            thread.quitSafely()
        }

        private fun ensureCodecIfPossible() {
            if (codec != null) return
            val spsBytes = sps ?: return
            val ppsBytes = pps ?: return

            val dims = H264SpsParser.tryParseDimensions(spsBytes)
            val w = dims?.first ?: 0
            val h = dims?.second ?: 0
            if (w <= 0 || h <= 0) {
                droppedAccessUnits += 1
                return
            }
            width = w
            height = h

            entry.surfaceTexture().setDefaultBufferSize(width, height)
            val outSurface = Surface(entry.surfaceTexture())
            surface = outSurface

            val format = MediaFormat.createVideoFormat("video/avc", width, height)
            format.setByteBuffer("csd-0", ByteBuffer.wrap(AnnexB.withStartCode(spsBytes)))
            format.setByteBuffer("csd-1", ByteBuffer.wrap(AnnexB.withStartCode(ppsBytes)))
            if (Build.VERSION.SDK_INT >= 23) {
                format.setInteger(MediaFormat.KEY_OPERATING_RATE, Short.MAX_VALUE.toInt())
            }
            format.setInteger(MediaFormat.KEY_FRAME_RATE, fps.coerceAtLeast(1))

            val c = MediaCodec.createDecoderByType("video/avc")
            c.configure(format, outSurface, null, 0)
            c.start()
            codec = c
        }

        private fun stopCodec() {
            decoding = false
            codec?.let { c ->
                try {
                    c.stop()
                } catch (_: Exception) {
                }
                try {
                    c.release()
                } catch (_: Exception) {
                }
            }
            codec = null
            surface?.let { s ->
                try {
                    s.release()
                } catch (_: Exception) {
                }
            }
            surface = null
        }

        private fun decode(accessUnit: ByteArray, codec: MediaCodec) {
            decoding = true
            val inputIndex = codec.dequeueInputBuffer(0)
            if (inputIndex < 0) {
                droppedAccessUnits += 1
                return
            }
            val buf = codec.getInputBuffer(inputIndex) ?: run {
                droppedAccessUnits += 1
                return
            }
            buf.clear()
            if (accessUnit.size > buf.remaining()) {
                droppedAccessUnits += 1
                codec.queueInputBuffer(inputIndex, 0, 0, 0, 0)
                return
            }
            buf.put(accessUnit)
            val ptsUs = (frameIndex * 1_000_000L) / fps.coerceAtLeast(1)
            frameIndex += 1
            codec.queueInputBuffer(inputIndex, 0, accessUnit.size, ptsUs, 0)

            val bufferInfo = MediaCodec.BufferInfo()
            while (true) {
                val outIndex = codec.dequeueOutputBuffer(bufferInfo, 0)
                if (outIndex >= 0) {
                    codec.releaseOutputBuffer(outIndex, true)
                    decodedFrames += 1
                    continue
                }
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val fmt = codec.outputFormat
                    val w = fmt.getInteger(MediaFormat.KEY_WIDTH)
                    val h = fmt.getInteger(MediaFormat.KEY_HEIGHT)
                    if (w > 0 && h > 0) {
                        width = w
                        height = h
                        entry.surfaceTexture().setDefaultBufferSize(width, height)
                    }
                    continue
                }
                break
            }
        }
    }

    private object AnnexB {
        private val startCode3 = byteArrayOf(0, 0, 1)
        private val startCode4 = byteArrayOf(0, 0, 0, 1)

        fun parseAccessUnit(accessUnit: ByteArray): List<ByteArray> {
            val starts = mutableListOf<Int>()
            var i = 0
            while (i + 3 < accessUnit.size) {
                if (accessUnit[i] == 0.toByte()
                    && accessUnit[i + 1] == 0.toByte()
                    && accessUnit[i + 2] == 1.toByte()
                ) {
                    starts.add(i)
                    i += 3
                    continue
                }
                if (i + 4 < accessUnit.size
                    && accessUnit[i] == 0.toByte()
                    && accessUnit[i + 1] == 0.toByte()
                    && accessUnit[i + 2] == 0.toByte()
                    && accessUnit[i + 3] == 1.toByte()
                ) {
                    starts.add(i)
                    i += 4
                    continue
                }
                i += 1
            }
            if (starts.isEmpty()) return emptyList()
            val out = ArrayList<ByteArray>(starts.size)
            for (idx in starts.indices) {
                val start = starts[idx]
                val next = if (idx + 1 < starts.size) starts[idx + 1] else accessUnit.size
                var headerLen = 3
                if (start + 3 < accessUnit.size
                    && accessUnit[start] == 0.toByte()
                    && accessUnit[start + 1] == 0.toByte()
                    && accessUnit[start + 2] == 0.toByte()
                    && accessUnit[start + 3] == 1.toByte()
                ) {
                    headerLen = 4
                }
                val nalStart = start + headerLen
                if (nalStart >= next) continue
                val nal = accessUnit.copyOfRange(nalStart, next)
                if (nal.isNotEmpty()) out.add(nal)
            }
            return out
        }

        fun withStartCode(nal: ByteArray): ByteArray {
            val out = ByteArray(startCode4.size + nal.size)
            System.arraycopy(startCode4, 0, out, 0, startCode4.size)
            System.arraycopy(nal, 0, out, startCode4.size, nal.size)
            return out
        }
    }

    private object H264SpsParser {
        fun tryParseDimensions(spsNal: ByteArray): Pair<Int, Int>? {
            if (spsNal.isEmpty()) return null
            val payload = removeEmulationPrevention(spsNal.copyOfRange(1, spsNal.size))
            val br = BitReader(payload)
            val profileIdc = br.readBits(8)
            br.readBits(8)
            br.readBits(8)
            br.readUE()
            var chromaFormatIdc = 1
            if (profileIdc in intArrayOf(100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 144)) {
                chromaFormatIdc = br.readUE()
                if (chromaFormatIdc == 3) {
                    br.readBits(1)
                }
                br.readUE()
                br.readUE()
                br.readBits(1)
                val scaling = br.readBits(1) == 1
                if (scaling) {
                    val count = if (chromaFormatIdc == 3) 12 else 8
                    for (i in 0 until count) {
                        val present = br.readBits(1) == 1
                        if (present) {
                            skipScalingList(br, if (i < 6) 16 else 64)
                        }
                    }
                }
            }
            br.readUE()
            val picOrderCntType = br.readUE()
            if (picOrderCntType == 0) {
                br.readUE()
            } else if (picOrderCntType == 1) {
                br.readBits(1)
                br.readSE()
                br.readSE()
                val cycle = br.readUE()
                for (i in 0 until cycle) br.readSE()
            }
            br.readUE()
            br.readBits(1)
            val picWidthInMbsMinus1 = br.readUE()
            val picHeightInMapUnitsMinus1 = br.readUE()
            val frameMbsOnlyFlag = br.readBits(1)
            if (frameMbsOnlyFlag == 0) br.readBits(1)
            br.readBits(1)
            val frameCroppingFlag = br.readBits(1)
            var cropLeft = 0
            var cropRight = 0
            var cropTop = 0
            var cropBottom = 0
            if (frameCroppingFlag == 1) {
                cropLeft = br.readUE()
                cropRight = br.readUE()
                cropTop = br.readUE()
                cropBottom = br.readUE()
            }
            var width = (picWidthInMbsMinus1 + 1) * 16
            var height = (picHeightInMapUnitsMinus1 + 1) * 16 * (2 - frameMbsOnlyFlag)

            val cropUnitX: Int
            val cropUnitY: Int
            when (chromaFormatIdc) {
                0 -> {
                    cropUnitX = 1
                    cropUnitY = 2 - frameMbsOnlyFlag
                }
                1 -> {
                    cropUnitX = 2
                    cropUnitY = 2 * (2 - frameMbsOnlyFlag)
                }
                2 -> {
                    cropUnitX = 2
                    cropUnitY = 2 - frameMbsOnlyFlag
                }
                else -> {
                    cropUnitX = 1
                    cropUnitY = 2 - frameMbsOnlyFlag
                }
            }
            width -= (cropLeft + cropRight) * cropUnitX
            height -= (cropTop + cropBottom) * cropUnitY

            if (width <= 0 || height <= 0) return null
            return Pair(width, height)
        }

        private fun removeEmulationPrevention(data: ByteArray): ByteArray {
            val out = ByteArray(data.size)
            var outLen = 0
            var zeros = 0
            for (b in data) {
                val ub = b.toInt() and 0xFF
                if (zeros == 2 && ub == 3) {
                    zeros = 0
                    continue
                }
                out[outLen++] = b
                zeros = if (ub == 0) zeros + 1 else 0
            }
            return out.copyOf(outLen)
        }

        private fun skipScalingList(br: BitReader, size: Int) {
            var lastScale = 8
            var nextScale = 8
            for (j in 0 until size) {
                if (nextScale != 0) {
                    val deltaScale = br.readSE()
                    nextScale = (lastScale + deltaScale + 256) % 256
                }
                lastScale = if (nextScale == 0) lastScale else nextScale
            }
        }
    }

    private class BitReader(private val data: ByteArray) {
        private var byteOffset = 0
        private var bitOffset = 0

        fun readBits(count: Int): Int {
            var n = count
            var out = 0
            while (n > 0) {
                if (byteOffset >= data.size) return out
                val current = data[byteOffset].toInt() and 0xFF
                val remaining = 8 - bitOffset
                val take = if (n < remaining) n else remaining
                val shift = remaining - take
                val mask = (0xFF shr (8 - take)) shl shift
                out = (out shl take) or ((current and mask) shr shift)
                bitOffset += take
                if (bitOffset == 8) {
                    bitOffset = 0
                    byteOffset += 1
                }
                n -= take
            }
            return out
        }

        fun readUE(): Int {
            var zeros = 0
            while (readBits(1) == 0 && zeros < 32) zeros += 1
            val suffix = if (zeros > 0) readBits(zeros) else 0
            return (1 shl zeros) - 1 + suffix
        }

        fun readSE(): Int {
            val v = readUE()
            val sign = if ((v and 1) == 0) -1 else 1
            return sign * ((v + 1) / 2)
        }
    }
}
