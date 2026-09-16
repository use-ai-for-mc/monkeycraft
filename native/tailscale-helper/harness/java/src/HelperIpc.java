import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

final class HelperIpc implements AutoCloseable {
  private final Process process;
  private final BufferedWriter stdin;
  private final BlockingQueue<String> lines = new LinkedBlockingQueue<String>();
  private final StringBuilder stderr = new StringBuilder();
  private final Thread stdoutDrain;
  private final Thread stderrDrain;

  HelperIpc(Path binary, boolean fake) throws IOException {
    List<String> cmd = new ArrayList<String>();
    cmd.add(binary.toAbsolutePath().toString());
    if (fake) {
      cmd.add("-fake");
    }
    ProcessBuilder pb = new ProcessBuilder(cmd);
    pb.redirectErrorStream(false);
    this.process = pb.start();
    this.stdin =
        new BufferedWriter(
            new OutputStreamWriter(process.getOutputStream(), StandardCharsets.UTF_8));
    this.stdoutDrain =
        new Thread(
            () -> {
              try (BufferedReader r =
                  new BufferedReader(
                      new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = r.readLine()) != null) {
                  lines.add(line);
                }
              } catch (IOException ignored) {
              }
            },
            "helper-stdout");
    stdoutDrain.setDaemon(true);
    stdoutDrain.start();
    this.stderrDrain =
        new Thread(
            () -> {
              try (BufferedReader r =
                  new BufferedReader(
                      new InputStreamReader(process.getErrorStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = r.readLine()) != null) {
                  synchronized (stderr) {
                    if (stderr.length() < 8192) {
                      stderr.append(line).append('\n');
                    }
                  }
                }
              } catch (IOException ignored) {
              }
            },
            "helper-stderr");
    stderrDrain.setDaemon(true);
    stderrDrain.start();
  }

  void send(String jsonLine) throws IOException {
    synchronized (stdin) {
      stdin.write(jsonLine);
      stdin.write('\n');
      stdin.flush();
    }
  }

  String readLine(Duration timeout) throws IOException, InterruptedException {
    String line = lines.poll(timeout.toMillis(), TimeUnit.MILLISECONDS);
    if (line == null) {
      throw new IOException("timeout waiting for helper stdout; stderr=" + stderrText());
    }
    return line;
  }

  void closeStdin() throws IOException {
    stdin.close();
  }

  boolean waitFor(Duration timeout) throws InterruptedException {
    return process.waitFor(timeout.toMillis(), TimeUnit.MILLISECONDS);
  }

  void destroyForcibly() {
    process.destroyForcibly();
  }

  @Override
  public void close() {
    if (process.isAlive()) {
      process.destroy();
      try {
        if (!process.waitFor(2, TimeUnit.SECONDS)) {
          process.destroyForcibly();
          process.waitFor(2, TimeUnit.SECONDS);
        }
      } catch (InterruptedException e) {
        process.destroyForcibly();
        Thread.currentThread().interrupt();
      }
    }
  }

  String stderrText() {
    synchronized (stderr) {
      return stderr.toString();
    }
  }

  static void requireNoSecrets(String s) {
    String lower = s.toLowerCase(Locale.ROOT);
    if (lower.contains("tskey-") || lower.contains("login.tailscale.com/a/")) {
      throw new AssertionError("possible secret in diagnostic output");
    }
  }
}
