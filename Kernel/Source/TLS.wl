(* wl-disable UnloadedContext *)
BeginPackage["ToneAr`WebSocketLink`FileScope`TLS`", {
	"ToneAr`WebSocketLink`",
	"ToneAr`WebSocketLink`Private`"
}];

Begin["`Private`"];

(* ---- JLink Initialization ---- *)

$tlsInitialized = False;
$tlsDefaultKeyStore = None;
$tlsDefaultPassword = "";
$tlsHelperVersion = "2026-04-25-1";
$tlsJVMArguments = StringRiffle[{
	"--add-opens java.base/sun.security.ssl=ALL-UNNAMED",
	"--add-opens java.base/sun.security.pkcs12=ALL-UNNAMED",
	"--add-opens java.base/sun.security.util=ALL-UNNAMED"
}, " "];
$tlsRootDirectory = ExpandFileName @ FileNameJoin[{DirectoryName[$InputFileName], "..", ".."}];
$tlsJarPath = FileNameJoin[{$tlsRootDirectory, "Java", "WebSocketTLS.jar"}];

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

initializeTLS[] := Module[{version, hasRequiredOpens, restarted = False},
	Needs["JLink`"];
	If[!FileExistsQ[$tlsJarPath],
		Return[Failure["WebSocketLink`TLS", <|
			"MessageTemplate" -> "TLS helper JAR not found at ``.",
			"MessageParameters" -> {$tlsJarPath}
		|>]]
	];
	If[TrueQ[$tlsInitialized], Return[True]];
	Quiet[
		JLink`InstallJava[
			JLink`JVMArguments -> $tlsJVMArguments,
			JLink`ClassPath -> {$tlsJarPath}
		],
		{JLink`InstallJava::reinst}
	];
	JLink`AddToClassPath[$tlsJarPath, Prepend -> True];
	JLink`LoadJavaClass["websocketlink.WebSocketTLS"];
	version = Quiet @ Check[WebSocketTLS`getHelperVersion[], $Failed];
	hasRequiredOpens = TrueQ @ Quiet @ Check[WebSocketTLS`hasRequiredModuleOpens[], False];
	If[version =!= $tlsHelperVersion || !hasRequiredOpens,
		restarted = True;
		JLink`ReinstallJava[
			JLink`JVMArguments -> $tlsJVMArguments,
			JLink`ClassPath -> {$tlsJarPath}
		];
		JLink`AddToClassPath[$tlsJarPath, Prepend -> True];
		JLink`LoadJavaClass["websocketlink.WebSocketTLS"];
		version = Quiet @ Check[WebSocketTLS`getHelperVersion[], $Failed];
		hasRequiredOpens = TrueQ @ Quiet @ Check[WebSocketTLS`hasRequiredModuleOpens[], False];
		If[version =!= $tlsHelperVersion || !hasRequiredOpens,
			Return[Failure["WebSocketLink`TLS", <|
				"MessageTemplate" -> "Loaded TLS helper version `` with required module opens = `` does not match expected version `` from ``.",
				"MessageParameters" -> {version, hasRequiredOpens, $tlsHelperVersion, $tlsJarPath}
			|>]]
		]
	];
	If[restarted,
		$tlsDefaultKeyStore = None;
		$tlsDefaultPassword = "";
	];
	$tlsInitialized = True;
	True
];

(* ---- Certificate Resolution ---- *)

(* Resolve "Certificate" option value to a {KeyStore, password} pair *)
resolveCertConfig[Automatic] := Module[{initResult},
	initResult = initializeTLS[];
	If[FailureQ[initResult], Return[{$Failed, $tlsDefaultPassword}]];
	If[$tlsDefaultKeyStore === None,
		$tlsDefaultKeyStore = WebSocketTLS`generateSelfSignedKeyStore[$keytoolPath];
		If[$tlsDefaultKeyStore === $Failed,
			Return[{$Failed, WebSocketTLS`getDefaultPassword[]}]
		];
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

makeTLSServerContext[certConfig_] := Module[{initResult, ks, password},
	initResult = initializeTLS[];
	If[FailureQ[initResult], Return[initResult]];
	{ks, password} = resolveCertConfig[certConfig];
	If[FailureQ[ks] || ks === $Failed || !TrueQ[JLink`JavaObjectQ[ks]],
		Return[Failure["WebSocketLink`TLS", <|
			"MessageTemplate" -> "Failed to resolve TLS server certificate configuration."
		|>]]
	];
	WebSocketTLS`createServerSSLContext[ks, password]
];

makeTLSClientContext[verifyPeer_, certConfig_: Automatic] := Module[{initResult, ctx},
	initResult = initializeTLS[];
	If[FailureQ[initResult], Return[initResult]];
	ctx = Which[
		!TrueQ[verifyPeer],
			WebSocketTLS`createClientSSLContext[False],
		certConfig === Automatic && TrueQ[JLink`JavaObjectQ[$tlsDefaultKeyStore]],
			WebSocketTLS`createClientSSLContextWithTrustStore[$tlsDefaultKeyStore],
		True,
			WebSocketTLS`createClientSSLContext[True]
	];
	If[ctx === $Failed || !TrueQ[JLink`JavaObjectQ[ctx]],
		Return[Failure["WebSocketLink`TLS", <|
			"MessageTemplate" -> "Failed to create TLS client context."
		|>]]
	];
	ctx
];

(* ---- Proxy Entry Points ---- *)

(*
 * Start TLS server proxy on externalPort.
 * Returns {sslServerSocket, loopbackPort}.
 * Server.wl calls SocketListen on loopbackPort; Java accept loop
 * pipes each incoming SSL connection through to that loopback port.
 *)
StartTLSServerProxy[externalPort_Integer, certConfig_] := Module[{
		initResult, sslCtx, sslServerSocket, loopbackPort
	},
	initResult = initializeTLS[];
	If[FailureQ[initResult], Return[initResult]];
	sslCtx = makeTLSServerContext[certConfig];
	If[FailureQ[sslCtx] || sslCtx === $Failed,
		Return[sslCtx]
	];
	sslServerSocket = WebSocketTLS`createSSLServerSocket[sslCtx, externalPort];
	If[sslServerSocket === $Failed || !TrueQ[JLink`JavaObjectQ[sslServerSocket]],
		Return[Failure["WebSocketLink`TLS", <|
			"MessageTemplate" -> "Failed to create TLS server socket on port ``.",
			"MessageParameters" -> {externalPort}
		|>]]
	];
	loopbackPort = WebSocketTLS`findAvailableLoopbackPort[];
	If[!IntegerQ[loopbackPort],
		Return[Failure["WebSocketLink`TLS", <|
			"MessageTemplate" -> "Failed to allocate a loopback port for the TLS server proxy."
		|>]]
	];
	WebSocketTLS`startServerAcceptLoop[sslServerSocket, loopbackPort];
	{sslServerSocket, loopbackPort}
];

(*
 * Connect via TLS to host:port, expose as a plain loopback socket.
 * Returns loopbackPort. Client.wl calls SocketConnect["localhost:<loopbackPort>"].
 *)
StartTLSClientProxy[host_String, port_Integer, certConfig_, verifyPeer_: True] := Module[{
		initResult, sslCtx, sslSocket, loopbackServer, loopbackPort
	},
	initResult = initializeTLS[];
	If[FailureQ[initResult], Return[initResult]];
	sslCtx = makeTLSClientContext[verifyPeer, certConfig];
	If[FailureQ[sslCtx] || sslCtx === $Failed,
		Return[sslCtx]
	];
	sslSocket = WebSocketTLS`createClientSSLSocket[sslCtx, host, port];
	If[sslSocket === $Failed || !TrueQ[JLink`JavaObjectQ[sslSocket]],
		Return[Failure["WebSocketLink`TLS", <|
			"MessageTemplate" -> "Failed to create TLS client socket for ``:``.",
			"MessageParameters" -> {host, port}
		|>]]
	];
	loopbackServer = WebSocketTLS`createLoopbackServer[];
	If[loopbackServer === $Failed || !TrueQ[JLink`JavaObjectQ[loopbackServer]],
		Return[Failure["WebSocketLink`TLS", <|
			"MessageTemplate" -> "Failed to create the TLS client loopback server."
		|>]]
	];
	loopbackPort = WebSocketTLS`getServerSocketPort[loopbackServer];
	If[!IntegerQ[loopbackPort],
		Return[Failure["WebSocketLink`TLS", <|
			"MessageTemplate" -> "Failed to determine the TLS client loopback port."
		|>]]
	];
	WebSocketTLS`startClientProxyAccept[sslSocket, loopbackServer];
	loopbackPort
];

End[];
EndPackage[];
