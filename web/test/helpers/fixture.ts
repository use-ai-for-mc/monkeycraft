// Loader for fixtures produced by tools/record-session.ts.

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

export const fixturesRoot = join(import.meta.dirname, "..", "fixtures");

export interface TextLine {
  t: number;
  dir: "in" | "out";
  text: string;
}

export interface BinLine {
  t: number;
  dir: "in";
  bin: { offset: number; length: number; kind: string; idr?: boolean; header?: [number, number] };
}

export type FixtureLine = TextLine | BinLine;

export interface Fixture {
  name: string;
  lines: FixtureLine[];
  binary: Uint8Array;
  meta: { seconds: number; counts: Record<string, number>; binaryBytes: number };
}

export function listFixtures(): string[] {
  if (!existsSync(fixturesRoot)) return [];
  return readdirSync(fixturesRoot, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .sort();
}

export function loadFixture(name: string): Fixture {
  const dir = join(fixturesRoot, name);
  const lines = readFileSync(join(dir, "session.jsonl"), "utf8")
    .split("\n")
    .filter((l) => l.length > 0)
    .map((l) => JSON.parse(l) as FixtureLine);
  const binary = new Uint8Array(readFileSync(join(dir, "binary.bin")));
  const meta = JSON.parse(readFileSync(join(dir, "meta.json"), "utf8")) as Fixture["meta"];
  return { name, lines, binary, meta };
}

export function isText(line: FixtureLine): line is TextLine {
  return "text" in line;
}

export function binaryOf(fixture: Fixture, line: BinLine): Uint8Array {
  return fixture.binary.subarray(line.bin.offset, line.bin.offset + line.bin.length);
}
