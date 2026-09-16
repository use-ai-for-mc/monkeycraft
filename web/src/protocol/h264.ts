// Annex-B helpers for the access units the mod sends (docs/PROTOCOL.md 5.1).

export const NAL_SLICE = 1;
export const NAL_IDR = 5;
export const NAL_SPS = 7;
export const NAL_PPS = 8;

/** Index of the byte after a 3- or 4-byte start code beginning at `i`, or -1. */
function startCodeEnd(au: Uint8Array, i: number): number {
  if (au[i] !== 0 || au[i + 1] !== 0) return -1;
  if (au[i + 2] === 1) return i + 3;
  if (au[i + 2] === 0 && au[i + 3] === 1) return i + 4;
  return -1;
}

/** Yields [nalStart, nalEnd) byte ranges for every NAL unit in the access unit. */
export function* nalUnits(au: Uint8Array): Generator<[number, number]> {
  let start = -1;
  let i = 0;
  while (i + 2 < au.length) {
    const end = startCodeEnd(au, i);
    if (end === -1) {
      i++;
      continue;
    }
    if (start !== -1) {
      // Trailing zero bytes belong to the next start code, not to this NAL.
      let nalEnd = i;
      while (nalEnd > start && au[nalEnd - 1] === 0) nalEnd--;
      yield [start, nalEnd];
    }
    start = end;
    i = end;
  }
  if (start !== -1 && start < au.length) yield [start, au.length];
}

export function nalTypes(au: Uint8Array): number[] {
  const types: number[] = [];
  for (const [s] of nalUnits(au)) {
    const header = au[s];
    if (header !== undefined) types.push(header & 0x1f);
  }
  return types;
}

export function containsIdr(au: Uint8Array): boolean {
  for (const [s] of nalUnits(au)) {
    const header = au[s];
    if (header !== undefined && (header & 0x1f) === NAL_IDR) return true;
  }
  return false;
}

/** The first SPS NAL unit (header byte included), or null. */
export function findSps(au: Uint8Array): Uint8Array | null {
  for (const [s, e] of nalUnits(au)) {
    const header = au[s];
    if (header !== undefined && (header & 0x1f) === NAL_SPS) return au.subarray(s, e);
  }
  return null;
}

/** `avc1.PPCCLL` from the three bytes after the SPS NAL header. */
export function codecStringFromSps(sps: Uint8Array): string | null {
  if (sps.length < 4) return null;
  const hex = (b: number | undefined) => (b ?? 0).toString(16).padStart(2, "0");
  return `avc1.${hex(sps[1])}${hex(sps[2])}${hex(sps[3])}`;
}

export function bytesEqual(a: Uint8Array | null, b: Uint8Array | null): boolean {
  if (a === null || b === null) return a === b;
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}
