import { describe, expect, it } from "vitest";
import { splitBinaryFrame } from "../../src/protocol/frames.ts";
import {
  bytesEqual,
  codecStringFromSps,
  containsIdr,
  findSps,
  nalTypes,
} from "../../src/protocol/h264.ts";

const SC4 = [0, 0, 0, 1];
const SC3 = [0, 0, 1];
// jcodec baseline 4.0 SPS header: type 7, profile 0x42, constraints 0x00, level 0x28
const SPS = [0x67, 0x42, 0x00, 0x28, 0x8d];
const PPS = [0x68, 0xce, 0x38, 0x80];
const IDR = [0x65, 0x88, 0x84, 0x00];
const P = [0x41, 0x9a, 0x02];

function au(...parts: number[][]): Uint8Array {
  return Uint8Array.from(parts.flat());
}

describe("h264", () => {
  const idrAu = au(SC4, SPS, SC4, PPS, SC4, IDR);

  it("lists NAL types across 3- and 4-byte start codes", () => {
    expect(nalTypes(idrAu)).toEqual([7, 8, 5]);
    expect(nalTypes(au(SC3, P))).toEqual([1]);
    expect(nalTypes(au(SC4, P, SC3, P))).toEqual([1, 1]);
  });

  it("does not misread payload zeros as start codes", () => {
    const tricky = au(SC4, [0x41, 0x00, 0x00, 0x02, 0x01], SC4, P);
    expect(nalTypes(tricky)).toEqual([1, 1]);
  });

  it("detects IDR and extracts the SPS", () => {
    expect(containsIdr(idrAu)).toBe(true);
    expect(containsIdr(au(SC4, P))).toBe(false);
    const sps = findSps(idrAu);
    expect(sps && Array.from(sps)).toEqual(SPS);
    expect(findSps(au(SC4, P))).toBeNull();
  });

  it("derives the codec string from SPS bytes", () => {
    expect(codecStringFromSps(Uint8Array.from(SPS))).toBe("avc1.420028");
    expect(codecStringFromSps(Uint8Array.from([0x67, 0x42, 0xc0, 0x28]))).toBe("avc1.42c028");
    expect(codecStringFromSps(Uint8Array.from([0x67]))).toBeNull();
  });

  it("compares byte arrays", () => {
    expect(bytesEqual(Uint8Array.from(SPS), Uint8Array.from(SPS))).toBe(true);
    expect(bytesEqual(Uint8Array.from(SPS), Uint8Array.from(PPS))).toBe(false);
    expect(bytesEqual(null, null)).toBe(true);
    expect(bytesEqual(null, Uint8Array.from(SPS))).toBe(false);
  });
});

describe("splitBinaryFrame", () => {
  it("strips the MC resolution header", () => {
    const frame = splitBinaryFrame(au([0x4d, 0x43, 0x02, 0xd0, 0x05, 0x00], SC4, SPS));
    expect(frame.kind).toBe("video");
    if (frame.kind !== "video") return;
    expect(frame.width).toBe(720);
    expect(frame.height).toBe(1280);
    expect(nalTypes(frame.au)).toEqual([7]);
  });

  it("passes bare access units through", () => {
    const frame = splitBinaryFrame(au(SC4, P));
    expect(frame).toMatchObject({ kind: "video" });
    if (frame.kind === "video") {
      expect(frame.width).toBeUndefined();
      expect(frame.au.length).toBe(7);
    }
  });

  it("parses map frames", () => {
    const buf = new ArrayBuffer(2 + 8 + 8 + 4 + 2 + 4 + 2 + (1 + 8 + 8 + 4 + 2 + 4));
    const view = new DataView(buf);
    const bytes = new Uint8Array(buf);
    bytes[0] = 0x4d;
    bytes[1] = 0x4d;
    let off = 2;
    view.setFloat64(off, 10.5);
    off += 8;
    view.setFloat64(off, -3.25);
    off += 8;
    view.setFloat32(off, 90);
    off += 4;
    view.setInt16(off, 4);
    off += 2;
    bytes.set([0x61, 0x62, 0x63, 0x64], off);
    off += 4;
    view.setInt16(off, 1);
    off += 2;
    view.setUint8(off, 2);
    off += 1;
    view.setFloat64(off, 1);
    off += 8;
    view.setFloat64(off, 2);
    off += 8;
    view.setInt32(off, 4242);
    off += 4;
    view.setInt16(off, 4);
    off += 2;
    bytes.set([0x62, 0x6f, 0x61, 0x74], off);

    const frame = splitBinaryFrame(bytes);
    expect(frame.kind).toBe("map");
    if (frame.kind !== "map") return;
    expect(frame.playerX).toBe(10.5);
    expect(frame.playerZ).toBe(-3.25);
    expect(frame.playerYaw).toBe(90);
    expect(frame.playerUuid).toBe("abcd");
    expect(frame.entities).toEqual([{ type: 2, x: 1, z: 2, entityId: 4242, name: "boat" }]);
  });

  it("flags anything else as unknown", () => {
    expect(splitBinaryFrame(Uint8Array.from([1, 2, 3])).kind).toBe("unknown");
    expect(splitBinaryFrame(Uint8Array.from([0x4d, 0x4d, 0])).kind).toBe("unknown");
  });
});
