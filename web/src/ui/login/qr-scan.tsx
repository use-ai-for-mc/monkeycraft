import { useSignal } from "@preact/signals";
import { useEffect, useRef } from "preact/hooks";
import { decodeQrFromCanvas, drawScaled } from "../../platform/qr.ts";

interface Props {
  onResult: (value: string) => void;
  onClose: () => void;
}

const POLL_MS = 350;

/** Camera QR scanner with an image-file fallback (screenshots of the in-game QR). */
export function QrScan({ onResult, onClose }: Props) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const error = useSignal<string | null>(null);
  const busy = useSignal(false);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    let stream: MediaStream | null = null;
    let timer: ReturnType<typeof setInterval> | null = null;
    let done = false;
    const canvas = document.createElement("canvas");
    (async () => {
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "environment" },
          audio: false,
        });
        video.srcObject = stream;
        await video.play();
        timer = setInterval(async () => {
          if (done || video.readyState < 2) return;
          drawScaled(canvas, video);
          const value = await decodeQrFromCanvas(canvas);
          if (value && !done) {
            done = true;
            onResult(value);
          }
        }, POLL_MS);
      } catch (err) {
        error.value = `Camera unavailable: ${String((err as Error).message ?? err)}`;
      }
    })();
    return () => {
      done = true;
      if (timer) clearInterval(timer);
      for (const t of stream?.getTracks() ?? []) t.stop();
    };
  }, [onResult, error]);

  const onFile = async (e: Event) => {
    const file = (e.currentTarget as HTMLInputElement).files?.[0];
    if (!file) return;
    busy.value = true;
    try {
      const bitmap = await createImageBitmap(file);
      const canvas = document.createElement("canvas");
      drawScaled(canvas, bitmap);
      bitmap.close();
      const value = await decodeQrFromCanvas(canvas);
      if (value) onResult(value);
      else error.value = "No QR code found in that image.";
    } catch (err) {
      error.value = `Could not read image: ${String(err)}`;
    } finally {
      busy.value = false;
    }
  };

  return (
    <div class="qr" data-testid="qr-scan">
      <header>
        <button type="button" onClick={onClose} aria-label="Close scanner">
          ‹
        </button>
        <h2>Scan the QR code</h2>
      </header>
      <video ref={videoRef} playsInline muted />
      <p class="muted">Point the camera at the QR shown in Minecraft, or choose a screenshot.</p>
      <label class="file">
        <input type="file" accept="image/*" onChange={onFile} disabled={busy.value} />
        Choose image
      </label>
      {error.value && <p class="error">{error.value}</p>}
    </div>
  );
}
