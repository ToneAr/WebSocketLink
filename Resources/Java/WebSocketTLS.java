package websocketlink;

import javax.net.ssl.*;
import java.io.*;
import java.net.*;
import java.security.*;
import java.security.cert.Certificate;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.Base64;
import java.util.regex.*;

public class WebSocketTLS {
    static final String DEFAULT_PASSWORD = "websocketlink_tls_internal";

    // ---- Certificate / KeyStore ----

    public static KeyStore generateSelfSignedKeyStore(String keytoolPath) throws Exception {
        File tmp = File.createTempFile("wsl_ks_", ".p12");
        tmp.deleteOnExit();
        ProcessBuilder pb = new ProcessBuilder(
            keytoolPath,
            "-genkeypair", "-alias", "wsl",
            "-keyalg", "RSA", "-keysize", "2048",
            "-validity", "3650",
            "-keystore", tmp.getAbsolutePath(),
            "-storepass", DEFAULT_PASSWORD,
            "-keypass",  DEFAULT_PASSWORD,
            "-dname", "CN=localhost,O=WebSocketLink",
            "-storetype", "PKCS12"
        );
        pb.redirectErrorStream(true);
        Process p = pb.start();
        byte[] buf = new byte[1024];
        try (InputStream is = p.getInputStream()) {
            while (is.read(buf) != -1) {}
        }
        int exit = p.waitFor();
        if (exit != 0) throw new Exception("keytool exited with code " + exit);
        KeyStore ks = KeyStore.getInstance("PKCS12");
        try (FileInputStream fis = new FileInputStream(tmp)) {
            ks.load(fis, DEFAULT_PASSWORD.toCharArray());
        }
        return ks;
    }

    public static String getDefaultPassword() { return DEFAULT_PASSWORD; }

    public static KeyStore loadPKCS12KeyStore(String path, String password) throws Exception {
        KeyStore ks = KeyStore.getInstance("PKCS12");
        try (FileInputStream fis = new FileInputStream(path)) {
            ks.load(fis, password.toCharArray());
        }
        return ks;
    }

    public static KeyStore loadPEMKeyStore(String pemContent) throws Exception {
        byte[] certBytes = extractPEM(pemContent, "CERTIFICATE");
        byte[] keyBytes  = extractPEM(pemContent, "PRIVATE KEY");
        if (certBytes == null) throw new Exception("No CERTIFICATE block in PEM");
        if (keyBytes  == null) throw new Exception("No PRIVATE KEY block in PEM");
        CertificateFactory cf = CertificateFactory.getInstance("X.509");
        Certificate cert = cf.generateCertificate(new ByteArrayInputStream(certBytes));
        PrivateKey key;
        try {
            key = KeyFactory.getInstance("RSA").generatePrivate(new PKCS8EncodedKeySpec(keyBytes));
        } catch (Exception e) {
            key = KeyFactory.getInstance("EC").generatePrivate(new PKCS8EncodedKeySpec(keyBytes));
        }
        KeyStore ks = KeyStore.getInstance("PKCS12");
        ks.load(null, null);
        ks.setKeyEntry("wsl", key, "".toCharArray(), new Certificate[]{cert});
        return ks;
    }

    private static byte[] extractPEM(String pem, String type) {
        Matcher m = Pattern.compile(
            "-----BEGIN " + type + "-----([^-]+)-----END " + type + "-----",
            Pattern.DOTALL).matcher(pem);
        return m.find() ? Base64.getDecoder().decode(m.group(1).replaceAll("\\s+", "")) : null;
    }

    // ---- SSL Contexts ----

    public static SSLContext createServerSSLContext(KeyStore ks, String password) throws Exception {
        KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        kmf.init(ks, password.toCharArray());
        SSLContext ctx = SSLContext.getInstance("TLS");
        ctx.init(kmf.getKeyManagers(), null, null);
        return ctx;
    }

    public static SSLContext createClientSSLContext(boolean verifyPeer) throws Exception {
        SSLContext ctx = SSLContext.getInstance("TLS");
        TrustManager[] tms;
        if (verifyPeer) {
            TrustManagerFactory tmf = TrustManagerFactory.getInstance(
                TrustManagerFactory.getDefaultAlgorithm());
            tmf.init((KeyStore) null);
            tms = tmf.getTrustManagers();
        } else {
            tms = new TrustManager[]{ new X509TrustManager() {
                public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
                public void checkClientTrusted(X509Certificate[] c, String a) {}
                public void checkServerTrusted(X509Certificate[] c, String a) {}
            }};
        }
        ctx.init(null, tms, null);
        return ctx;
    }

    // ---- Socket creation ----

    public static SSLServerSocket createSSLServerSocket(SSLContext ctx, int port) throws Exception {
        return (SSLServerSocket) ctx.getServerSocketFactory().createServerSocket(port);
    }

    public static SSLSocket createClientSSLSocket(SSLContext ctx, String host, int port)
            throws Exception {
        SSLSocket sock = (SSLSocket) ctx.getSocketFactory().createSocket(host, port);
        sock.startHandshake();
        return sock;
    }

    public static ServerSocket createLoopbackServer() throws Exception {
        return new ServerSocket(0, 1, InetAddress.getLoopbackAddress());
    }

    public static int getServerSocketPort(ServerSocket ss) { return ss.getLocalPort(); }

    public static int findAvailableLoopbackPort() throws Exception {
        try (ServerSocket ss = new ServerSocket(0, 1, InetAddress.getLoopbackAddress())) {
            return ss.getLocalPort();
        }
    }

    // ---- Proxy threads ----

    public static void startServerAcceptLoop(SSLServerSocket sslServerSocket, int loopbackPort) {
        Thread t = new Thread(() -> {
            while (!sslServerSocket.isClosed()) {
                try {
                    SSLSocket sslConn = (SSLSocket) sslServerSocket.accept();
                    Socket plain = connectWithRetry("127.0.0.1", loopbackPort, 50, 20);
                    if (plain == null) { sslConn.close(); continue; }
                    startBidirectionalPipe(sslConn, plain);
                } catch (IOException e) {
                    if (!sslServerSocket.isClosed())
                        System.err.println("[WebSocketLink TLS] accept error: " + e.getMessage());
                }
            }
        }, "WSLink-TLS-Accept");
        t.setDaemon(true);
        t.start();
    }

    public static void startClientProxyAccept(SSLSocket sslSocket, ServerSocket loopbackServer) {
        Thread t = new Thread(() -> {
            try {
                Socket plain = loopbackServer.accept();
                try { loopbackServer.close(); } catch (IOException ignored) {}
                startBidirectionalPipe(sslSocket, plain);
            } catch (IOException e) {
                System.err.println("[WebSocketLink TLS] client proxy error: " + e.getMessage());
            }
        }, "WSLink-TLS-Client");
        t.setDaemon(true);
        t.start();
    }

    // ---- Private helpers ----

    private static Socket connectWithRetry(String host, int port, int retries, int delayMs) {
        for (int i = 0; i < retries; i++) {
            try { return new Socket(host, port); }
            catch (IOException e) {
                try { Thread.sleep(delayMs); } catch (InterruptedException ignored) {}
            }
        }
        return null;
    }

    private static void startBidirectionalPipe(Socket a, Socket b) {
        Runnable close = () -> {
            try { a.close(); } catch (IOException ignored) {}
            try { b.close(); } catch (IOException ignored) {}
        };
        startOnePipe(a, b, close);
        startOnePipe(b, a, close);
    }

    private static void startOnePipe(Socket from, Socket to, Runnable onClose) {
        Thread t = new Thread(() -> {
            byte[] buf = new byte[4096];
            int n;
            try {
                InputStream  in  = from.getInputStream();
                OutputStream out = to.getOutputStream();
                while ((n = in.read(buf)) >= 0) { out.write(buf, 0, n); out.flush(); }
            } catch (IOException ignored) {
            } finally { onClose.run(); }
        }, "WSLink-TLS-Pipe");
        t.setDaemon(true);
        t.start();
    }
}
