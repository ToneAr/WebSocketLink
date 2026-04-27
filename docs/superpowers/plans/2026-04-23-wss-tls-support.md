# WSS/TLS Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add WSS (WebSocket Secure) support to both `WebSocketServerStart` and `WebSocketConnect` using a JLink-based in-process TLS proxy so no external tools need to be installed.

**Architecture:** A pre-compiled Java helper class (`WebSocketTLS.jar`) bundled in `Resources/Java/` handles SSL context creation, self-signed cert generation via `keytool`, and bidirectional piping between SSL sockets and plain loopback sockets. `TLS.wl` wraps this via JLink. Server and client code remain largely unchanged — they connect to a loopback port that the TLS layer transparently bridges to the real SSL connection.

**Tech Stack:** Wolfram Language, JLink (WL's built-in Java bridge), Java 21 (WL 15.0 bundled JDK), `javax.net.ssl`, `java.net`, system `keytool` (bundled with WL's JDK).

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `Resources/Java/WebSocketTLS.java` | Java helper: cert gen, SSL contexts, proxy threads |
| Create | `Resources/Java/WebSocketTLS.jar` | Pre-compiled JAR (produced from above) |
| Create | `Kernel/Source/TLS.wl` | JLink wrapper: init, cert config resolution, proxy entry points |
| Modify | `Kernel/Private.wl` | Declare `StartTLSServerProxy`/`StartTLSClientProxy` symbols in shared context |
| Modify | `Kernel/Public.wl` | Declare new public option symbols |
| Modify | `Kernel/Source/Server.wl` | Add `"TLS"`, `"Certificate"`, `"CertificatePassword"` options |
| Modify | `Kernel/Source/Client.wl` | Replace `openssl s_client` branch with TLS proxy |
| Modify | `Kernel/Source/Objects.wl` | Close `SSLServerSocket` in `Close` upvalue |
| Modify | `PacletInfo.wl` | Register `WebSocketTLS.jar` as an asset |

---

## Task 1: Write Java helper source

**Files:**
- Create: `Resources/Java/WebSocketTLS.java`

- [ ] **Step 1: Write `WebSocketTLS.java`**

```java
package websocketlink;

import javax.net.ssl.*;
import java.io.*;
import java.net.*;
import java.security.*;
import java.security.cert.*;
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
```

- [ ] **Step 2: Commit source file**

```bash
git add Resources/Java/WebSocketTLS.java
git commit -m "feat: add WebSocketTLS Java helper source"
```

---

## Task 2: Compile Java helper to JAR

**Files:**
- Create: `Resources/Java/WebSocketTLS.jar`

- [ ] **Step 1: Compile with WL's bundled javac**

```bash
WL_JAVAC="/home/tonya/Wolfram/Wolfram/15.0/SystemFiles/Java/Linux-x86-64/bin/javac"
WL_JAR="/home/tonya/Wolfram/Wolfram/15.0/SystemFiles/Java/Linux-x86-64/bin/jar"
cd /home/tonya/Working/resource-projects/resource-paclets/resource-paclet-WEBSOCKET-LINK/Resources/Java
mkdir -p classes
$WL_JAVAC -d classes WebSocketTLS.java
```

Expected: no output (success), `classes/websocketlink/WebSocketTLS.class` created.

- [ ] **Step 2: Package into JAR**

```bash
cd /home/tonya/Working/resource-projects/resource-paclets/resource-paclet-WEBSOCKET-LINK/Resources/Java
$WL_JAR cf WebSocketTLS.jar -C classes .
```

Expected: `WebSocketTLS.jar` created (~5KB).

- [ ] **Step 3: Verify JAR contents**

```bash
$WL_JAR tf WebSocketTLS.jar
```

Expected output includes `websocketlink/WebSocketTLS.class`.

- [ ] **Step 4: Commit JAR**

```bash
cd /home/tonya/Working/resource-projects/resource-paclets/resource-paclet-WEBSOCKET-LINK
git add Resources/Java/WebSocketTLS.jar
git commit -m "feat: add compiled WebSocketTLS.jar"
```

---

## Task 3: Register JAR as paclet asset

**Files:**
- Modify: `PacletInfo.wl`

- [ ] **Step 1: Add Java asset to PacletInfo.wl**

In `PacletInfo.wl`, change the `"Asset"` extension from:

```mathematica
{"Asset",
    "Root" -> "Resources",
    "Assets" -> {
        { "logo.svg", "Icons/logo.svg" }
    }
}
```

to:

```mathematica
{"Asset",
    "Root" -> "Resources",
    "Assets" -> {
        { "logo.svg", "Icons/logo.svg" },
        { "WebSocketTLS.jar", "Java/WebSocketTLS.jar" }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add PacletInfo.wl
git commit -m "feat: register WebSocketTLS.jar as paclet asset"
```

---

## Task 4: Declare shared TLS symbols in Private.wl

**Files:**
- Modify: `Kernel/Private.wl`

The `ToneAr`WebSocketLink`Private`` context is in every source file's dependency list. Declaring symbols here gives them a fixed home accessible across all source files.

- [ ] **Step 1: Add TLS symbol declarations to `Kernel/Private.wl`**

Change `Kernel/Private.wl` from:

```mathematica
BeginPackage["ToneAr`WebSocketLink`Private`"];

LF = "\n";
CR = "\r";
CRLF = "\r\n";

intToBitList::usage = "Convert an integer to a list of bits";
bitListToInt::usage = "Convert a list of bits to an integer";
webSocketObjectQ::usage = "Check if an object is a WebSocketObject";

EndPackage[];
```

to:

```mathematica
BeginPackage["ToneAr`WebSocketLink`Private`"];

LF = "\n";
CR = "\r";
CRLF = "\r\n";

intToBitList::usage = "Convert an integer to a list of bits";
bitListToInt::usage = "Convert a list of bits to an integer";
webSocketObjectQ::usage = "Check if an object is a WebSocketObject";

StartTLSServerProxy::usage = "Internal: start TLS server proxy, return {sslSocket, loopbackPort}";
StartTLSClientProxy::usage = "Internal: start TLS client proxy, return loopbackPort";

EndPackage[];
```

- [ ] **Step 2: Commit**

```bash
git add Kernel/Private.wl
git commit -m "feat: declare TLS proxy symbols in shared Private context"
```

---

## Task 5: Create TLS.wl

**Files:**
- Create: `Kernel/Source/TLS.wl`

- [ ] **Step 1: Write `Kernel/Source/TLS.wl`**

```mathematica
(* :!CodeAnalysis::BeginBlock:: *)
(* :!CodeAnalysis::Disable::SuspiciousSessionSymbol:: *)
BeginPackage["ToneAr`WebSocketLink`FileScope`TLS`", {
	"ToneAr`WebSocketLink`",
	"ToneAr`WebSocketLink`Private`"
}];

Begin["`Private`"];

(* ---- JLink Initialization ---- *)

$tlsInitialized = False;
$tlsDefaultKeyStore = None;
$tlsDefaultPassword = "";

$keytoolPath := With[{
		javaHome = JavaSystemProperty["java.home"],
		ext = If[$OperatingSystem === "Windows", ".exe", ""]
	},
	FileNameJoin[{javaHome, "bin", "keytool" <> ext}]
];

initializeTLS[] := If[!TrueQ[$tlsInitialized],
	Needs["JLink`"];
	InstallJava[];
	With[{
		jarPath = PacletObject["ToneAr/WebSocketLink"]["AssetLocation", "WebSocketTLS.jar"]
	},
		AddToClassPath[jarPath]
	];
	LoadJavaClass["websocketlink.WebSocketTLS"];
	$tlsInitialized = True
];

(* ---- Certificate Resolution ---- *)

(* Resolve "Certificate" option value to a {KeyStore, password} pair *)
resolveCertConfig[Automatic] := Module[{},
	initializeTLS[];
	If[$tlsDefaultKeyStore === None,
		$tlsDefaultKeyStore = WebSocketTLS`generateSelfSignedKeyStore[$keytoolPath];
		$tlsDefaultPassword = WebSocketTLS`getDefaultPassword[]
	];
	{$tlsDefaultKeyStore, $tlsDefaultPassword}
];

resolveCertConfig[path_String] := (
	initializeTLS[];
	Which[
		StringEndsQ[path, ".p12" | ".pfx"],
			{WebSocketTLS`loadPKCS12KeyStore[path, ""], ""},
		StringEndsQ[path, ".pem"] && FileExistsQ[path],
			{WebSocketTLS`loadPEMKeyStore[ReadString[path]], ""},
		StringContainsQ[path, "-----BEGIN"],
			{WebSocketTLS`loadPEMKeyStore[path], ""},
		True,
			Failure["WebSocketLink`TLS", <|
				"MessageTemplate" -> "Cannot determine certificate format: ``.",
				"MessageParameters" -> {path}
			|>]
	]
);

resolveCertConfig[{path_String, password_String}] := (
	initializeTLS[];
	{WebSocketTLS`loadPKCS12KeyStore[path, password], password}
);

(* ---- SSL Context Creation ---- *)

makeTLSServerContext[certConfig_] := Module[{ks, password},
	initializeTLS[];
	{ks, password} = resolveCertConfig[certConfig];
	WebSocketTLS`createServerSSLContext[ks, password]
];

makeTLSClientContext[verifyPeer_] := (
	initializeTLS[];
	WebSocketTLS`createClientSSLContext[verifyPeer]
);

(* ---- Proxy Entry Points ---- *)

(*
 * Start TLS server proxy on externalPort.
 * Returns {sslServerSocket, loopbackPort}.
 * Server.wl calls SocketListen on loopbackPort.
 * Java accept loop pipes each SSL connection to loopbackPort.
 *)
StartTLSServerProxy[externalPort_Integer, certConfig_] := Module[{
		sslCtx, sslServerSocket, loopbackPort
	},
	initializeTLS[];
	sslCtx = makeTLSServerContext[certConfig];
	sslServerSocket = WebSocketTLS`createSSLServerSocket[sslCtx, externalPort];
	loopbackPort = WebSocketTLS`findAvailableLoopbackPort[];
	WebSocketTLS`startServerAcceptLoop[sslServerSocket, loopbackPort];
	{sslServerSocket, loopbackPort}
];

(*
 * Connect via TLS to host:port, expose as plain loopback socket.
 * Returns loopbackPort. Client.wl calls SocketConnect["localhost:loopbackPort"].
 *)
StartTLSClientProxy[host_String, port_Integer, certConfig_, verifyPeer_: True] := Module[{
		sslCtx, sslSocket, loopbackServer, loopbackPort
	},
	initializeTLS[];
	sslCtx = makeTLSClientContext[verifyPeer];
	sslSocket = WebSocketTLS`createClientSSLSocket[sslCtx, host, port];
	loopbackServer = WebSocketTLS`createLoopbackServer[];
	loopbackPort = WebSocketTLS`getServerSocketPort[loopbackServer];
	WebSocketTLS`startClientProxyAccept[sslSocket, loopbackServer];
	loopbackPort
];

End[];
EndPackage[];
(* :!CodeAnalysis::EndBlock:: *)
```

- [ ] **Step 2: Commit**

```bash
git add Kernel/Source/TLS.wl
git commit -m "feat: add TLS.wl JLink wrapper for WSS proxy"
```

---

## Task 6: Update Server.wl for TLS

**Files:**
- Modify: `Kernel/Source/Server.wl`

- [ ] **Step 1: Add TLS options and proxy call to `Server.wl`**

Change the top of `Server.wl` (BeginPackage declaration) from:

```mathematica
BeginPackage["ToneAr`WebSocketLink`FileScope`Server`", {
	"ToneAr`WebSocketLink`",
	"ToneAr`WebSocketLink`Private`"
}];
```

to:

```mathematica
BeginPackage["ToneAr`WebSocketLink`FileScope`Server`", {
	"ToneAr`WebSocketLink`",
	"ToneAr`WebSocketLink`Private`"
}];
```

(No change to BeginPackage — TLS symbols are in `Private`` context which is already a dependency.)

Change the options declaration from:

```mathematica
WebSocketServerStart // Options = {
	"GUID" -> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11",
	"Debug" -> False,
	OverwriteTarget -> True,
	"HandlerFunctions" -> <|
		"DataReceived" -> Identity,
		"ClientConnected" -> Identity,
		"ClientDisconnected" -> Identity
	|>
};
WebSocketServerStart[port_Integer : Automatic, OptionsPattern[]] := Module[{
		listenerFunction, listener, serverObj, server,
		debugPrint = If[OptionValue["Debug"],
			Print,
			Identity
		],
		connectedClients = <||>,
		serverUUID = CreateUUID[]
	},
	Enclose[
		If[OptionValue[OverwriteTarget],
			Quiet @ Close @ SelectFirst[Sockets[], Function[wso,
				wso["DestinationPort"] === port
			]]
		];
```

to:

```mathematica
WebSocketServerStart // Options = {
	"GUID" -> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11",
	"Debug" -> False,
	OverwriteTarget -> True,
	"TLS" -> False,
	"Certificate" -> Automatic,
	"CertificatePassword" -> "",
	"HandlerFunctions" -> <|
		"DataReceived" -> Identity,
		"ClientConnected" -> Identity,
		"ClientDisconnected" -> Identity
	|>
};
WebSocketServerStart[port_Integer : Automatic, OptionsPattern[]] := Module[{
		listenerFunction, listener, serverObj, server,
		debugPrint = If[OptionValue["Debug"],
			Print,
			Identity
		],
		connectedClients = <||>,
		serverUUID = CreateUUID[],
		sslServerSocket = None,
		listenPort
	},
	Enclose[
		listenPort = port;
		If[TrueQ @ OptionValue["TLS"],
			With[{
				certConfig = Replace[OptionValue["Certificate"], {
					Automatic -> Automatic,
					p_String :> If[OptionValue["CertificatePassword"] =!= "",
						{p, OptionValue["CertificatePassword"]}, p
					]
				}]
			},
				{sslServerSocket, listenPort} =
					Confirm[
						StartTLSServerProxy[port, certConfig],
						"Failed to start TLS server proxy"
					]
			]
		];

		If[OptionValue[OverwriteTarget],
			Quiet @ Close @ SelectFirst[Sockets[], Function[wso,
				wso["DestinationPort"] === listenPort
			]]
		];
```

Then change the `SocketListen` call from:

```mathematica
		listener = Confirm @ SocketListen[port, listenerFunction];
```

to:

```mathematica
		listener = Confirm @ SocketListen[listenPort, listenerFunction];
```

Then change `serverObj` construction from:

```mathematica
		serverObj = <|
			"Type"     -> "WebSocketServer",
			"Listener" -> listener,
			"Socket"   -> listener["Socket"],
			"UUID"     -> serverUUID,
			"Port"     -> listener["Socket"]["DestinationPort"],
			"ConnectedClients" :> connectedClients,
			"HandlerFunctions" -> OptionValue["HandlerFunctions"]
		|>;
```

to:

```mathematica
		serverObj = <|
			"Type"            -> "WebSocketServer",
			"Listener"        -> listener,
			"Socket"          -> listener["Socket"],
			"UUID"            -> serverUUID,
			"Port"            -> If[TrueQ @ OptionValue["TLS"], port,
			                       listener["Socket"]["DestinationPort"]],
			"TLS"             -> TrueQ @ OptionValue["TLS"],
			"SSLServerSocket" -> sslServerSocket,
			"ConnectedClients" :> connectedClients,
			"HandlerFunctions" -> OptionValue["HandlerFunctions"]
		|>;
```

- [ ] **Step 2: Commit**

```bash
git add Kernel/Source/Server.wl
git commit -m "feat: add TLS/WSS support to WebSocketServerStart"
```

---

## Task 7: Update Client.wl for TLS

**Files:**
- Modify: `Kernel/Source/Client.wl`

- [ ] **Step 1: Add `"VerifyPeer"` option and replace openssl branch**

Change the options declaration from:

```mathematica
WebSocketConnect // Options = {
	"GUID" -> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11",
	"MaxStoredMessages" -> 1000
};
```

to:

```mathematica
WebSocketConnect // Options = {
	"GUID" -> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11",
	"MaxStoredMessages" -> 1000,
	"VerifyPeer" -> True
};
```

Replace the entire `server = If[parsedUrl["Scheme"] === "https", ...]` block:

```mathematica
		server = If[parsedUrl["Scheme"] === "https",
			ConfirmMatch[
				StartProcess[{"openssl", "s_client", "-connect",
					parsedUrl["Domain"] <> ":" <> ToString[upgradeRequest["Port"]]
				}],
				_ProcessObject,
				StringTemplate["Failed to connect to WebSocket server at '``' using openssl."][
					address
				]
			],
			ConfirmMatch[
				SocketConnect[address],
				_SocketObject,
				StringTemplate["Failed to connect to WebSocket server at '``'."][
					address
				]
			]
		];
```

with:

```mathematica
		server = If[parsedUrl["Scheme"] === "https",
			With[{
				loopbackPort = Confirm[
					StartTLSClientProxy[
						parsedUrl["Domain"],
						Replace[parsedUrl["Port"],
							None :> If[parsedUrl["Scheme"] === "https", 443, 80]
						],
						Automatic,
						OptionValue["VerifyPeer"]
					],
					StringTemplate["Failed to start TLS proxy for '``'."][address]
				]
			},
				ConfirmMatch[
					SocketConnect["localhost:" <> ToString[loopbackPort]],
					_SocketObject,
					StringTemplate["Failed to connect loopback socket for '``'."][address]
				]
			],
			ConfirmMatch[
				SocketConnect[address],
				_SocketObject,
				StringTemplate["Failed to connect to WebSocket server at '``'."][address]
			]
		];
```

Also remove the `https` scheme response parsing block (which used `openssl` output stripping) and replace it with the same plain socket handling as the `ws://` path. The two branches after the handshake request is sent currently differ:

```mathematica
		If[parsedUrl["Scheme"] === "https",
			handshakeResp = ImportString[
				StringReplace[
					ReadString[server, CRLF<>CRLF]<>CRLF<>CRLF,
					{
						___ ~~ "---\n" ~~ a : ("HTTP" ~~ ___ ~~ CRLF ~~ CRLF) :> a
					}
				],
				"HTTPResponse"
			] // Echo
			,
			While[!SocketReadyQ[server],
				Pause[0.00001]
			];
			handshakeResp = ImportString[ReadString[server], "HTTPResponse"];
		];
```

Replace this entire block with the plain socket approach (no scheme check needed anymore since both paths now use a plain loopback socket):

```mathematica
		While[!SocketReadyQ[server],
			Pause[0.00001]
		];
		handshakeResp = ImportString[ReadString[server], "HTTPResponse"];
```

- [ ] **Step 2: Commit**

```bash
git add Kernel/Source/Client.wl
git commit -m "feat: replace openssl WSS branch with JLink TLS proxy in WebSocketConnect"
```

---

## Task 8: Update Objects.wl for TLS cleanup

**Files:**
- Modify: `Kernel/Source/Objects.wl`

- [ ] **Step 1: Close SSLServerSocket on server shutdown**

In `Objects.wl`, find the `Close`/`DeleteObject` upvalue:

```mathematica
WebSocketObject /: (Close|DeleteObject)[
	WebSocketObject[assoc : _Association?webSocketObjectQ]
] := (
	Switch[assoc["Type"],
		"WebSocketClient",
			BinaryWrite[assoc["Socket"], WebSocketFrameCreate[Close]],
		"WebSocketServer",
			$WebSocketServers = Select[$WebSocketServers, Function[wso,
				wso["UUID"] =!= assoc["UUID"]
			]];
	];
	Close @ assoc["Socket"]
);
```

Replace with:

```mathematica
WebSocketObject /: (Close|DeleteObject)[
	WebSocketObject[assoc : _Association?webSocketObjectQ]
] := (
	Switch[assoc["Type"],
		"WebSocketClient",
			BinaryWrite[assoc["Socket"], WebSocketFrameCreate[Close]],
		"WebSocketServer",
			$WebSocketServers = Select[$WebSocketServers, Function[wso,
				wso["UUID"] =!= assoc["UUID"]
			]];
			If[TrueQ[assoc["TLS"]] && assoc["SSLServerSocket"] =!= None,
				Quiet[assoc["SSLServerSocket"]@close[]]
			];
	];
	Close @ assoc["Socket"]
);
```

- [ ] **Step 2: Commit**

```bash
git add Kernel/Source/Objects.wl
git commit -m "feat: close SSLServerSocket on WebSocketObject close"
```

---

## Task 9: Manual integration test (WSS server + WSS client)

No automated test framework exists in the paclet. Verify by evaluating the following in WL after installing the paclet.

- [ ] **Step 1: Install paclet and test WSS server startup**

```mathematica
PacletInstall["/path/to/resource-paclet-WEBSOCKET-LINK", ForceVersionInstall -> True]
Needs["ToneAr`WebSocketLink`"]

server = WebSocketServerStart[8443, "TLS" -> True, 
  "HandlerFunctions" -> <|
    "DataReceived" -> Function[assoc, assoc["SendMessage"][assoc["Data"]]]
  |>
]
(* Expected: WebSocketObject[...] with Port -> 8443 and TLS -> True *)
```

- [ ] **Step 2: Connect WSS client and echo test**

```mathematica
client = WebSocketConnect["wss://localhost:8443", "VerifyPeer" -> False]
(* Expected: WebSocketObject with Type -> WebSocketClient *)

client["SendMessage"]["hello"]
Pause[0.1]
msg = client["GetMessage"]
(* Expected: msg === "hello" *)
```

- [ ] **Step 3: Close and verify cleanup**

```mathematica
Close[client]
Close[server]
(* Expected: both close without errors *)
```

- [ ] **Step 4: Commit any fixes found during testing**

```bash
git add -p
git commit -m "fix: address issues found during WSS integration test"
```
