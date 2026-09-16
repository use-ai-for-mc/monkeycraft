// Binary frame demultiplexing (docs/PROTOCOL.md section 5).

export interface VideoFrame {
  kind: "video";
  /** Present only when the frame carried the 6-byte `MC` resolution header. */
  width?: number;
  height?: number;
  au: Uint8Array;
}

export interface MapEntity {
  type: number;
  x: number;
  z: number;
  entityId: number;
  name: string;
}

export interface MapFrame {
  kind: "map";
  playerX: number;
  playerZ: number;
  playerYaw: number;
  playerUuid: string;
  entities: MapEntity[];
}

export interface UnknownFrame {
  kind: "unknown";
  data: Uint8Array;
}

export type BinaryFrame = VideoFrame | MapFrame | UnknownFrame;

const M = 0x4d;
const C = 0x43;
const MAP_MIN_LENGTH = 24;
const VIDEO_HEADER_LENGTH = 6;
const utf8 = new TextDecoder();

export function splitBinaryFrame(bytes: Uint8Array): BinaryFrame {
  if (bytes.length >= MAP_MIN_LENGTH && bytes[0] === M && bytes[1] === M) {
    const map = parseMapFrame(bytes);
    if (map) return map;
  }
  if (bytes.length >= VIDEO_HEADER_LENGTH && bytes[0] === M && bytes[1] === C) {
    const width = ((bytes[2] ?? 0) << 8) | (bytes[3] ?? 0);
    const height = ((bytes[4] ?? 0) << 8) | (bytes[5] ?? 0);
    return { kind: "video", width, height, au: bytes.subarray(VIDEO_HEADER_LENGTH) };
  }
  if (bytes.length >= 4 && bytes[0] === 0 && bytes[1] === 0) {
    return { kind: "video", au: bytes };
  }
  return { kind: "unknown", data: bytes };
}

function parseMapFrame(bytes: Uint8Array): MapFrame | null {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  try {
    let off = 2;
    const playerX = view.getFloat64(off);
    off += 8;
    const playerZ = view.getFloat64(off);
    off += 8;
    const playerYaw = view.getFloat32(off);
    off += 4;
    const uuidLen = view.getInt16(off);
    off += 2;
    const playerUuid = utf8.decode(bytes.subarray(off, off + uuidLen));
    off += uuidLen;
    const count = view.getInt16(off);
    off += 2;
    const entities: MapEntity[] = [];
    for (let i = 0; i < count; i++) {
      const type = view.getUint8(off);
      off += 1;
      const x = view.getFloat64(off);
      off += 8;
      const z = view.getFloat64(off);
      off += 8;
      const entityId = view.getInt32(off);
      off += 4;
      const nameLen = view.getInt16(off);
      off += 2;
      const name = utf8.decode(bytes.subarray(off, off + nameLen));
      off += nameLen;
      entities.push({ type, x, z, entityId, name });
    }
    return { kind: "map", playerX, playerZ, playerYaw, playerUuid, entities };
  } catch {
    return null;
  }
}
