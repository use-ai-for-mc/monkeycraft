import { TcpWebSocket } from './tcp-websocket.js';
import { H264Decoder } from '../../web/src/video/decoder.ts';
import { generateSalt, clientSignature, verifyServerSignature } from '../../web/src/protocol/auth.ts';

export async function probe(rpc, { host, port = 9600, password = 'test', seconds = 20, helloOnly = false, authenticate = null, waitForVideoSeconds = 0 }, progress = () => {}) {
  const started = performance.now();
  const socket = new TcpWebSocket(rpc);
  const stats = { host, port, backend: 'wasm', hello: false, authenticated: false, received: 0, decoded: 0, bytes: 0, errors: 0, videoState: '', durationMs: 0, connectMs: 0, firstFrameMs: null, maxFrameGapMs: 0, maxFrameBytes: 0, passed: false };
  let lastFrameAt = null;
  let streamStart = null;
  const decoder = new H264Decoder({
    onFrame(frame) {
      stats.decoded++;
      const now = performance.now();
      if (lastFrameAt !== null) stats.maxFrameGapMs = Math.max(stats.maxFrameGapMs, now - lastFrameAt);
      lastFrameAt = now;
      if (stats.firstFrameMs === null) stats.firstFrameMs = now - started;
      frame.close();
      progress({ ...stats });
    },
    onKeyframeNeeded() { void socket.send(JSON.stringify({ type: 'REQUEST_KEYFRAME' })).catch(() => {}); },
    onUnsupported(message) { throw new Error(message); },
    onStats(value) { stats.errors = value.errors; },
  });
  const watchdog = setTimeout(() => { void socket.close().catch(() => {}); }, (seconds + waitForVideoSeconds + 35) * 1000);
  try {
    await socket.open(host, port);
    stats.connectMs = performance.now() - started;
    const hello = JSON.parse(await socket.read());
    if (hello.type !== 'HELLO' || typeof hello.salt !== 'string') throw new Error('expected game HELLO');
    stats.hello = true;
    if (helloOnly) { stats.passed = true; return stats; }
    if (!await decoder.start()) throw new Error('H264 decoder unavailable');
    const salt = generateSalt();
    const proof = authenticate ? await authenticate(hello.salt, salt) : null;
    await socket.send(JSON.stringify({ type: 'AUTH', salt, signature: proof?.clientSignature ?? await clientSignature(password, hello.salt, salt), deviceName: 'WASM connection probe' }));
    while (true) {
      const message = await socket.read();
      if (typeof message === 'string') {
        const data = JSON.parse(message);
        if (data.type === 'AUTH_RESPONSE' && data.success === false) throw new Error('game authentication rejected');
        if (data.type === 'AUTH_OK') {
          const verified = proof ? data.signature === proof.serverSignature : await verifyServerSignature(password, hello.salt, salt, data.signature);
          if (!verified) throw new Error('server authentication rejected');
          stats.authenticated = true;
          streamStart = waitForVideoSeconds > 0 ? null : performance.now();
          await socket.send(JSON.stringify({ type: 'CLIENT_STATUS', mode: 'STREAMING', width: 360, height: 640, fps: 10, autoFaceMovement: false, dataSaver: true }));
        }
        if (data.type === 'SERVER_STATUS') stats.videoState = data.videoState;
        if (data.type === 'HEARTBEAT') await socket.send(JSON.stringify({ type: 'HEARTBEAT_ACK' }));
      } else {
        if (!stats.authenticated) throw new Error('video before authentication');
        if (streamStart === null) streamStart = performance.now();
        stats.received++;
        stats.bytes += message.length;
        stats.maxFrameBytes = Math.max(stats.maxFrameBytes, message.length);
        const unit = message[0] === 0x4d && message[1] === 0x43 ? message.subarray(6) : message;
        decoder.push(unit);
        await socket.send(JSON.stringify({ type: 'ACK' }));
      }
      progress({ ...stats });
      if (streamStart !== null && performance.now() - streamStart >= seconds * 1000) break;
    }
    stats.passed = stats.authenticated && stats.decoded > 0 && stats.errors === 0;
    return stats;
  } finally {
    clearTimeout(watchdog);
    decoder.close();
    await socket.close().catch(() => {});
    stats.durationMs = performance.now() - started;
    progress({ ...stats });
  }
}
