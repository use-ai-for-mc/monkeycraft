import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;

public final class HelperIpcTest {
  public static void main(String[] args) throws Exception {
    if (args.length < 1) {
      throw new IllegalArgumentException("usage: HelperIpcTest <helper-binary>");
    }
    Path bin = Path.of(args[0]);
    if (!Files.isRegularFile(bin)) {
      throw new IllegalArgumentException("missing helper binary: " + bin);
    }
    Path state = Files.createTempDirectory("mc-ts-java-");
    try (HelperIpc ipc = new HelperIpc(bin, true)) {
      ipc.send(
          "{\"protocolVersion\":1,\"sessionNonce\":\"java-harness\",\"requestId\":\"1\",\"command\":\"start\",\"target\":\"127.0.0.1:9600\",\"listenPort\":9600,\"stateDir\":\""
              + jsonEscape(state.toAbsolutePath().toString())
              + "\"}");
      String ready = ipc.readLine(Duration.ofSeconds(5));
      if (ready == null || !ready.contains("\"event\":\"ready\"")) {
        throw new AssertionError("expected ready, got " + ready + " stderr=" + ipc.stderrText());
      }
      if (!ready.contains("\"protocolVersion\":1")) {
        throw new AssertionError("missing protocolVersion: " + ready);
      }
      if (!ready.contains("\"sessionNonce\":\"java-harness\"")) {
        throw new AssertionError("missing nonce: " + ready);
      }
      ipc.send(
          "{\"protocolVersion\":1,\"sessionNonce\":\"java-harness\",\"requestId\":\"2\",\"command\":\"status\"}");
      String status = ipc.readLine(Duration.ofSeconds(5));
      if (status == null || !status.contains("\"event\"")) {
        throw new AssertionError("expected status event, got " + status);
      }
      ipc.send(
          "{\"protocolVersion\":1,\"sessionNonce\":\"java-harness\",\"requestId\":\"3\",\"command\":\"shutdown\"}");
      boolean stopped = false;
      for (int i = 0; i < 8; i++) {
        String line = ipc.readLine(Duration.ofSeconds(3));
        if (line != null && line.contains("\"event\":\"stopped\"")) {
          stopped = true;
          break;
        }
      }
      if (!stopped) {
        throw new AssertionError("expected stopped");
      }
      if (!ipc.waitFor(Duration.ofSeconds(3))) {
        ipc.destroyForcibly();
        throw new AssertionError("helper did not exit after shutdown");
      }
      HelperIpc.requireNoSecrets(ipc.stderrText());
    }

    try (HelperIpc ipc = new HelperIpc(bin, true)) {
      ipc.send(
          "{\"protocolVersion\":1,\"sessionNonce\":\"eof\",\"requestId\":\"1\",\"command\":\"status\"}");
      String ready = ipc.readLine(Duration.ofSeconds(5));
      if (ready == null || !ready.contains("\"event\":\"ready\"")) {
        throw new AssertionError("expected ready before EOF test");
      }
      ipc.closeStdin();
      if (!ipc.waitFor(Duration.ofSeconds(4))) {
        ipc.destroyForcibly();
        throw new AssertionError("helper did not exit after parent EOF");
      }
    }
    System.out.println("JAVA_HARNESS_OK java=" + System.getProperty("java.version"));
  }

  private static String jsonEscape(String s) {
    return s.replace("\\", "\\\\").replace("\"", "\\\"");
  }
}
