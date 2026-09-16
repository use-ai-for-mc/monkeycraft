// Sanity checks over every recorded fixture in test/fixtures. These make sure
// the recorder output is internally consistent and that the protocol parsers
// agree with what the recorder classified at capture time. Protocol golden
// tests (M1) build on the same loader.

import { describe, expect, it } from "vitest";
import { splitBinaryFrame } from "../../src/protocol/frames.ts";
import { containsIdr } from "../../src/protocol/h264.ts";
import { binaryOf, isText, listFixtures, loadFixture } from "../helpers/fixture.ts";

const fixtures = listFixtures();

describe.each(fixtures)("fixture %s", (name) => {
  const fixture = loadFixture(name);
  const { lines, binary, meta } = fixture;

  it("starts with HELLO, AUTH, AUTH_OK and contains no password", () => {
    const texts = lines.filter(isText);
    expect(texts.length).toBeGreaterThanOrEqual(3);
    const types = texts.slice(0, 3).map((l) => (JSON.parse(l.text) as { type: string }).type);
    expect(types).toEqual(["HELLO", "AUTH", "AUTH_OK"]);
    for (const l of texts) {
      const msg = JSON.parse(l.text) as Record<string, unknown>;
      if (typeof msg.password === "string") expect(msg.password).toBe("<redacted>");
    }
  });

  it("has monotonic timestamps and a contiguous binary index", () => {
    let lastT = -1;
    let offset = 0;
    for (const l of lines) {
      expect(l.t).toBeGreaterThanOrEqual(lastT);
      lastT = l.t;
      if (!isText(l)) {
        expect(l.bin.offset).toBe(offset);
        offset += l.bin.length;
      }
    }
    expect(offset).toBe(binary.length);
    expect(meta.binaryBytes).toBe(binary.length);
  });

  it("classifies binary frames the same way the recorder did", () => {
    for (const l of lines) {
      if (isText(l)) continue;
      const frame = splitBinaryFrame(binaryOf(fixture, l));
      expect(frame.kind).toBe(l.bin.kind);
      if (frame.kind === "video") {
        expect(containsIdr(frame.au)).toBe(l.bin.idr === true);
        if (l.bin.header) {
          expect([frame.width, frame.height]).toEqual(l.bin.header);
          expect(l.bin.idr).toBe(true);
        }
      }
    }
  });
});

it("has at least the hibernating fixture", () => {
  expect(fixtures).toContain("hibernating");
});
