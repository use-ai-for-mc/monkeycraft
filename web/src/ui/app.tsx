import { webOriginServer } from "../transport/endpoint.ts";

export function App() {
  const origin = webOriginServer(new URL(window.location.href));
  return (
    <main class="shell">
      <h1>MonkeyCraft</h1>
      <p class="muted">Web client scaffold. Server origin: {origin || "(none)"}</p>
    </main>
  );
}
