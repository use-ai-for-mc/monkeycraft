import com.monkeycraft.tailscale.TailscaleClient;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.URI;
import java.nio.file.Path;
import java.util.concurrent.CountDownLatch;

public final class LoopbackBridge {
  public static void main(String[] args) throws Exception {
    if (args.length != 5) {
      System.err.println(
          "Usage: LoopbackBridge <state-directory> <control-url> <hostname> <tailnet-port>"
              + " <loopback-port>");
      System.exit(2);
    }
    var config =
        new TailscaleClient.Config(
            Path.of(args[0]),
            URI.create(args[1]),
            args[2],
            Integer.parseInt(args[3]),
            new InetSocketAddress(InetAddress.getByName("127.0.0.1"), Integer.parseInt(args[4])));
    var done = new CountDownLatch(1);
    try (var client =
        new TailscaleClient(
            config,
            status -> {
              System.out.println("state=" + status.state() + " error=" + status.error());
              if (!status.authURL().isEmpty())
                System.out.println("Open this login URL locally: " + status.authURL());
            })) {
      Runtime.getRuntime()
          .addShutdownHook(
              new Thread(
                  () -> {
                    try {
                      client.close();
                    } catch (java.io.IOException e) {
                      System.err.println("Close failed: " + e.getClass().getSimpleName());
                    } finally {
                      done.countDown();
                    }
                  }));
      client.start();
      done.await();
    }
  }
}
