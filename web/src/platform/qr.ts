// QR decoding: BarcodeDetector when the browser has it, bundled jsQR otherwise.
// The MonkeyCraft QR encodes the password verbatim.

import jsQR from "jsqr";

interface DetectorLike {
  detect(source: ImageBitmapSource): Promise<Array<{ rawValue: string }>>;
}

declare global {
  interface Window {
    BarcodeDetector?: new (opts?: { formats?: string[] }) => DetectorLike;
  }
}

let detector: DetectorLike | null | undefined;

function nativeDetector(): DetectorLike | null {
  if (detector !== undefined) return detector;
  try {
    detector = window.BarcodeDetector ? new window.BarcodeDetector({ formats: ["qr_code"] }) : null;
  } catch {
    detector = null;
  }
  return detector;
}

/** Decode a QR code from a canvas that already holds the frame. Returns null when none is found. */
export async function decodeQrFromCanvas(canvas: HTMLCanvasElement): Promise<string | null> {
  const native = nativeDetector();
  if (native) {
    try {
      const codes = await native.detect(canvas);
      const value = codes[0]?.rawValue;
      if (value) return value;
    } catch {
      // fall through to jsQR
    }
  }
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  if (!ctx) return null;
  const image = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const result = jsQR(image.data, image.width, image.height, { inversionAttempts: "dontInvert" });
  return result?.data ?? null;
}

/** Draw an image or video frame into a canvas, downscaled so the long edge is at most `maxEdge`. */
export function drawScaled(
  canvas: HTMLCanvasElement,
  source: HTMLVideoElement | HTMLImageElement | ImageBitmap,
  maxEdge = 720,
): void {
  const sw =
    source instanceof HTMLVideoElement
      ? source.videoWidth
      : source instanceof HTMLImageElement
        ? source.naturalWidth
        : source.width;
  const sh =
    source instanceof HTMLVideoElement
      ? source.videoHeight
      : source instanceof HTMLImageElement
        ? source.naturalHeight
        : source.height;
  if (sw === 0 || sh === 0) return;
  const scale = Math.min(1, maxEdge / Math.max(sw, sh));
  canvas.width = Math.round(sw * scale);
  canvas.height = Math.round(sh * scale);
  canvas
    .getContext("2d", { willReadFrequently: true })
    ?.drawImage(source, 0, 0, canvas.width, canvas.height);
}
