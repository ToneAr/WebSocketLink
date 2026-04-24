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

(* Prefer WL's bundled keytool; fall back to system PATH *)
$keytoolPath := With[{
		ext = If[$OperatingSystem === "Windows", ".exe", ""],
		wlKeytool = FileNameJoin[{
			$InstallationDirectory, "SystemFiles", "Java",
			$SystemID, "bin", "keytool"
		}]
	},
	If[FileExistsQ[wlKeytool <> ext], wlKeytool <> ext, "keytool" <> ext]
];

initializeTLS[] := If[!TrueQ[$tlsInitialized],
	Needs["JLink`"];
	InstallJava[
		"JVMArguments" -> {
			"--add-opens=java.base/sun.security.ssl=ALL-UNNAMED",
			"--add-opens=java.base/sun.security.pkcs12=ALL-UNNAMED",
			"--add-opens=java.base/sun.security.util=ALL-UNNAMED"
		}
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
 * Server.wl calls SocketListen on loopbackPort; Java accept loop
 * pipes each incoming SSL connection through to that loopback port.
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
 * Connect via TLS to host:port, expose as a plain loopback socket.
 * Returns loopbackPort. Client.wl calls SocketConnect["localhost:<loopbackPort>"].
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
