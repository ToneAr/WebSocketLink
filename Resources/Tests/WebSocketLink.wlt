(* ============================================================
   ToneAr/WebSocketLink – Test Suite
   Run with:
     TestReport["Tests/WebSocketLink.wlt"]
   Prerequisites:
     - ResourceFunctions "ByteArrayToBitList" and "BitListToByteArray"
       must be cached (used internally by WebSocketFrameCreate/Import).
     - Integration tests (Section 5) require a free loopback TCP port.
   ============================================================ *)
PacletDirectoryLoad[ParentDirectory[#, 2]& @ DirectoryName @ $TestFileName]

Needs["ToneAr`WebSocketLink`"]

debug[msg_String] := If[$TestDebug, Print[msg]];

(* ================================================================
   Globals sanity
   ================================================================ *)
debug["Running: Globals-1-WebSocketClients-IsAssociation ..."];
VerificationTest[
	AssociationQ[$WebSocketClients],
	True,
	TestID -> "Globals-1-WebSocketClients-IsAssociation"
]

debug["Running: Globals-2-WebSocketServers-IsList ..."];
VerificationTest[
	ListQ[$WebSocketServers],
	True,
	TestID -> "Globals-2-WebSocketServers-IsList"
]

(* ================================================================
   Section 1 – Frame Encoding  (WebSocketFrameCreate)
   ================================================================ *)
debug["Running: FrameCreate-01-TextFrame-ResultType ..."];
VerificationTest[
	Head @ WebSocketFrameCreate["Hello"],
	ByteArray,
	TestID -> "FrameCreate-01-TextFrame-ResultType"
]

(* RFC 6455 exact bytes for "Hello":
   byte 0 = 0x81 → FIN=1, RSV=000, opcode=0001 (text)
   byte 1 = 0x05 → MASK=0, payload length = 5
   bytes 2-6 = ASCII codes of H e l l o *)
debug["Running: FrameCreate-02-TextFrame-ExactBytes ..."];
VerificationTest[
	Normal @ WebSocketFrameCreate["Hello"],
	{129, 5, 72, 101, 108, 108, 111},
	TestID -> "FrameCreate-02-TextFrame-ExactBytes"
]

debug["Running: FrameCreate-03-EmptyString ..."];
VerificationTest[
	Normal @ WebSocketFrameCreate[""],
	{129, 0},
	TestID -> "FrameCreate-03-EmptyString"
]

(* Binary opcode 0x2: byte 0 = 0x82 = 130 *)
debug["Running: FrameCreate-04-BinaryFrame-ExactBytes ..."];
VerificationTest[
	Normal @ WebSocketFrameCreate[ByteArray[{1, 2, 3}]],
	{130, 3, 1, 2, 3},
	TestID -> "FrameCreate-04-BinaryFrame-ExactBytes"
]

(* Ping: opcode 9 → byte 0 = 0x89 = 137 *)
debug["Running: FrameCreate-05-Ping ..."];
VerificationTest[
	Normal @ WebSocketFrameCreate[Ping],
	{137, 0},
	TestID -> "FrameCreate-05-Ping"
]

(* Pong: opcode 10 → byte 0 = 0x8A = 138 *)
debug["Running: FrameCreate-06-Pong ..."];
VerificationTest[
	Normal @ WebSocketFrameCreate[Pong],
	{138, 0},
	TestID -> "FrameCreate-06-Pong"
]

(* Close: opcode 8 → byte 0 = 0x88 = 136 *)
debug["Running: FrameCreate-07-Close ..."];
VerificationTest[
	Normal @ WebSocketFrameCreate[Close],
	{136, 0},
	TestID -> "FrameCreate-07-Close"
]

(* Masked text frame: 2 header + 4 masking-key + 5 payload = 11 bytes *)
debug["Running: FrameCreate-08-Masked-TotalLength ..."];
VerificationTest[
	Length @ WebSocketFrameCreate["Hello", Masking -> True],
	11,
	TestID -> "FrameCreate-08-Masked-TotalLength"
]

(* First byte (FIN + opcode) is the same whether or not masking is applied *)
debug["Running: FrameCreate-09-Masked-FirstByte ..."];
VerificationTest[
	First @ Normal @ WebSocketFrameCreate["Hello", Masking -> True],
	129,
	TestID -> "FrameCreate-09-Masked-FirstByte"
]

(* Second byte of a masked frame must have the MASK bit set (MSB = 1, value >= 128) *)
debug["Running: FrameCreate-10-Masked-MaskBitSet ..."];
VerificationTest[
	(Normal @ WebSocketFrameCreate["Hello", Masking -> True])[[2]] >= 128,
	True,
	TestID -> "FrameCreate-10-Masked-MaskBitSet"
]

(* 200-byte payload → 16-bit extended length tier:
   2 (header) + 2 (16-bit length) + 200 (payload) = 204 bytes total *)
debug["Running: FrameCreate-11-MediumPayload-TotalLength ..."];
VerificationTest[
	Length @ WebSocketFrameCreate[StringJoin @ ConstantArray["x", 200]],
	204,
	TestID -> "FrameCreate-11-MediumPayload-TotalLength"
]

(* The length-field sentinel byte for 16-bit extended length is 126 *)
debug["Running: FrameCreate-12-MediumPayload-SentinelByte ..."];
VerificationTest[
	(Normal @ WebSocketFrameCreate[StringJoin @ ConstantArray["x", 200]])[[2]],
	126,
	TestID -> "FrameCreate-12-MediumPayload-SentinelByte"
]

(* 70 000-byte payload → 64-bit extended length tier:
   2 (header) + 8 (64-bit length) + 70 000 (payload) = 70 010 bytes total *)
debug["Running: FrameCreate-13-LargePayload-TotalLength ..."];
VerificationTest[
	Length @ WebSocketFrameCreate[ByteArray @ ConstantArray[0, 70000]],
	70010,
	TestID -> "FrameCreate-13-LargePayload-TotalLength"
]

(* The length-field sentinel byte for 64-bit extended length is 127 *)
debug["Running: FrameCreate-14-LargePayload-SentinelByte ..."];
VerificationTest[
	(Normal @ WebSocketFrameCreate[ByteArray @ ConstantArray[0, 70000]])[[2]],
	127,
	TestID -> "FrameCreate-14-LargePayload-SentinelByte"
]

(* ================================================================
   Section 2 – Frame Decoding  (WebSocketFrameImport)
   ================================================================ *)
debug["Running: FrameImport-01-TextFrame ..."];
VerificationTest[
	WebSocketFrameImport[ByteArray[{129, 5, 72, 101, 108, 108, 111}]],
	"Hello",
	TestID -> "FrameImport-01-TextFrame"
]

debug["Running: FrameImport-02-BinaryFrame ..."];
VerificationTest[
	WebSocketFrameImport[ByteArray[{130, 3, 1, 2, 3}]],
	ByteArray[{1, 2, 3}],
	TestID -> "FrameImport-02-BinaryFrame"
]

debug["Running: FrameImport-03-EmptyTextFrame ..."];
VerificationTest[
	WebSocketFrameImport[ByteArray[{129, 0}]],
	"",
	TestID -> "FrameImport-03-EmptyTextFrame"
]

debug["Running: FrameImport-04-PingFrame ..."];
VerificationTest[
	WebSocketFrameImport[ByteArray[{137, 0}]],
	"Ping",
	TestID -> "FrameImport-04-PingFrame"
]

debug["Running: FrameImport-05-PongFrame ..."];
VerificationTest[
	WebSocketFrameImport[ByteArray[{138, 0}]],
	"Pong",
	TestID -> "FrameImport-05-PongFrame"
]

(* Close frame yields Null (signals connection teardown) *)
debug["Running: FrameImport-06-CloseFrame ..."];
VerificationTest[
	WebSocketFrameImport[ByteArray[{136, 0}]],
	Null,
	TestID -> "FrameImport-06-CloseFrame"
]

debug["Running: FrameImport-07-TextFrame-ResultType ..."];
VerificationTest[
	Head @ WebSocketFrameImport[ByteArray[{129, 5, 72, 101, 108, 108, 111}]],
	String,
	TestID -> "FrameImport-07-TextFrame-ResultType"
]

debug["Running: FrameImport-08-BinaryFrame-ResultType ..."];
VerificationTest[
	Head @ WebSocketFrameImport[ByteArray[{130, 3, 1, 2, 3}]],
	ByteArray,
	TestID -> "FrameImport-08-BinaryFrame-ResultType"
]

(* ================================================================
   Section 3 – Frame Round-Trips
   ================================================================ *)
debug["Running: RoundTrip-01-Text-Unmasked ..."];
VerificationTest[
	WebSocketFrameImport @ WebSocketFrameCreate["Hello, World!"],
	"Hello, World!",
	TestID -> "RoundTrip-01-Text-Unmasked"
]

debug["Running: RoundTrip-02-Text-Masked ..."];
VerificationTest[
	WebSocketFrameImport @
	WebSocketFrameCreate["Hello, World!", Masking -> True],
	"Hello, World!",
	TestID -> "RoundTrip-02-Text-Masked"
]

debug["Running: RoundTrip-03-Binary-Unmasked ..."];
VerificationTest[
	WebSocketFrameImport @
	WebSocketFrameCreate[ByteArray[{0, 1, 127, 128, 255}]],
	ByteArray[{0, 1, 127, 128, 255}],
	TestID -> "RoundTrip-03-Binary-Unmasked"
]

debug["Running: RoundTrip-04-Binary-Masked ..."];
VerificationTest[
	WebSocketFrameImport @
	WebSocketFrameCreate[ByteArray[{0, 1, 127, 128, 255}], Masking -> True],
	ByteArray[{0, 1, 127, 128, 255}],
	TestID -> "RoundTrip-04-Binary-Masked"
]

(* Multi-byte UTF-8: α β γ encode to 2 bytes each *)
debug["Running: RoundTrip-05-Unicode ..."];
VerificationTest[
	WebSocketFrameImport @ WebSocketFrameCreate["\[Alpha]\[Beta]\[Gamma]"],
	"\[Alpha]\[Beta]\[Gamma]",
	TestID -> "RoundTrip-05-Unicode"
]

(* All-zero bytes: distinguishes payload from length fields *)
debug["Running: RoundTrip-06-AllZeroBytes ..."];
VerificationTest[
	WebSocketFrameImport @
	WebSocketFrameCreate[ByteArray @ ConstantArray[0, 10]],
	ByteArray @ ConstantArray[0, 10],
	TestID -> "RoundTrip-06-AllZeroBytes"
]

(* All 256 byte values present in payload *)
debug["Running: RoundTrip-07-AllByteValues ..."];
VerificationTest[
	WebSocketFrameImport @ WebSocketFrameCreate[ByteArray @ Range[0, 255]],
	ByteArray @ Range[0, 255],
	TestID -> "RoundTrip-07-AllByteValues"
]

(* 16-bit extended payload length tier (300 bytes) *)
With[{
	s = StringJoin @ ConstantArray["a", 300]
},
	debug["Running: RoundTrip-08-MediumPayload ..."];
	VerificationTest[
		WebSocketFrameImport @ WebSocketFrameCreate[s],
		s,
		TestID -> "RoundTrip-08-MediumPayload"
	]
]

(* 64-bit extended payload length tier (70 000 bytes) *)
With[{
	ba = ByteArray @ Mod[Range[70000], 256]
},
	debug["Running: RoundTrip-09-LargePayload ..."];
	VerificationTest[
		WebSocketFrameImport @ WebSocketFrameCreate[ba],
		ba,
		TestID -> "RoundTrip-09-LargePayload"
	]
]

debug["Running: RoundTrip-10-Ping ..."];
VerificationTest[
	WebSocketFrameImport @ WebSocketFrameCreate[Ping],
	"Ping",
	TestID -> "RoundTrip-10-Ping"
]

debug["Running: RoundTrip-11-Pong ..."];
VerificationTest[
	WebSocketFrameImport @ WebSocketFrameCreate[Pong],
	"Pong",
	TestID -> "RoundTrip-11-Pong"
]

debug["Running: RoundTrip-12-Close ..."];
VerificationTest[
	WebSocketFrameImport @ WebSocketFrameCreate[Close],
	Null,
	TestID -> "RoundTrip-12-Close"
]

(* ================================================================
   Section 4 – WebSocketObject
   ================================================================ *)
(* --- webSocketObjectQ predicate --- *)
debug["Running: WSObjQ-01-ValidServerAssoc ..."];
VerificationTest[
	ToneAr`WebSocketLink`Private`webSocketObjectQ[
		<|
			"Type"             -> "WebSocketServer",
			"Listener"         -> None,
			"Socket"           -> None,
			"UUID"             -> "x",
			"Port"             -> 8080,
			"ConnectedClients" -> <||>,
			"HandlerFunctions" -> <||>
		|>
	],
	True,
	TestID -> "WSObjQ-01-ValidServerAssoc"
]

debug["Running: WSObjQ-02-ValidClientAssoc ..."];
VerificationTest[
	ToneAr`WebSocketLink`Private`webSocketObjectQ[
		<|
			"Type"        -> "WebSocketClient",
			"UUID"        -> "x",
			"Socket"      -> None,
			"Address"     -> "ws://localhost",
			"Messages"    -> None,
			"GetMessage"  :> None,
			"SendMessage" :> None
		|>
	],
	True,
	TestID -> "WSObjQ-02-ValidClientAssoc"
]

debug["Running: WSObjQ-03-ValidConnectedClientAssoc ..."];
VerificationTest[
	ToneAr`WebSocketLink`Private`webSocketObjectQ[
		<|
			"Type"        -> "WebSocketClientConnection",
			"UUID"        -> "x",
			"Socket"      -> None,
			"Messages"    -> None,
			"GetMessage"  :> None,
			"SendMessage" :> None
		|>
	],
	True,
	TestID -> "WSObjQ-03-ValidConnectedClientAssoc"
]

(* Missing required keys *)
debug["Running: WSObjQ-04-MissingKeys ..."];
VerificationTest[
	ToneAr`WebSocketLink`Private`webSocketObjectQ[<|"foo" -> "bar"|>],
	False,
	TestID -> "WSObjQ-04-MissingKeys"
]

(* Non-association *)
debug["Running: WSObjQ-05-NonAssocInput ..."];
VerificationTest[
	ToneAr`WebSocketLink`Private`webSocketObjectQ["notAnAssoc"],
	False,
	TestID -> "WSObjQ-05-NonAssocInput"
]

(* --- Property access, Properties list, Normal --- *)
With[{
	asc =
		<|
			"Type"        -> "WebSocketClient",
			"UUID"        -> "test-uuid",
			"Socket"      -> None,
			"Address"     -> "ws://localhost:9000",
			"Messages"    -> None,
			"GetMessage"  :> None,
			"SendMessage" :> None
		|>
},
	debug["Running: WSObjAccess-01-Type ..."];
	VerificationTest[
		WebSocketObject[asc]["Type"],
		"WebSocketClient",
		TestID -> "WSObjAccess-01-Type"
	];
	debug["Running: WSObjAccess-02-Address ..."];
	VerificationTest[
		WebSocketObject[asc]["Address"],
		"ws://localhost:9000",
		TestID -> "WSObjAccess-02-Address"
	];
	debug["Running: WSObjAccess-03-UUID ..."];
	VerificationTest[
		WebSocketObject[asc]["UUID"],
		"test-uuid",
		TestID -> "WSObjAccess-03-UUID"
	];
	debug["Running: WSObjAccess-04-MissingProperty ..."];
	VerificationTest[
		WebSocketObject[asc]["NonExistent"],
		Missing["NotFound", "NonExistent"],
		TestID -> "WSObjAccess-04-MissingProperty"
	];
	debug["Running: WSObjAccess-05-PropertiesList ..."];
	VerificationTest[
		Sort @ WebSocketObject[asc]["Properties"],
		Sort[
			{
				"Type",
				"UUID",
				"Socket",
				"Address",
				"Messages",
				"GetMessage",
				"SendMessage"
			}
		],
		TestID -> "WSObjAccess-05-PropertiesList"
	];
	debug["Running: WSObjAccess-06-Normal ..."];
	VerificationTest[
		Normal @ WebSocketObject[asc],
		asc,
		TestID -> "WSObjAccess-06-Normal"
	]
]

(* --- WriteString / BinaryWrite guards (server objects must be rejected) --- *)
With[{
	fakeServer =
		WebSocketObject[
			<|
				"Type"             -> "WebSocketServer",
				"Listener"         -> None,
				"Socket"           -> None,
				"UUID"             -> "x",
				"Port"             -> 8080,
				"ConnectedClients" -> <||>,
				"HandlerFunctions" -> <||>
			|>
		]
},
	debug["Running: WSObjGuard-01-WriteStringToServer-ReturnsFailure ..."];
	VerificationTest[
		FailureQ @ WriteString[fakeServer, "test"],
		True,
		TestID -> "WSObjGuard-01-WriteStringToServer-ReturnsFailure"
	];
	debug["Running: WSObjGuard-02-BinaryWriteToServer-ReturnsFailure ..."];
	VerificationTest[
		FailureQ @ BinaryWrite[fakeServer, ByteArray[{1, 2, 3}]],
		True,
		TestID -> "WSObjGuard-02-BinaryWriteToServer-ReturnsFailure"
	];
	debug["Running: WSObjGuard-03-ReadFromServer-ReturnsFailure ..."];
	VerificationTest[
		FailureQ @ Read[fakeServer],
		True,
		TestID -> "WSObjGuard-03-ReadFromServer-ReturnsFailure"
	]
]

(* ================================================================
   Section 5 – Integration Tests  (require loopback TCP)
   ================================================================ *)
$wsRxServer = {}; (* payloads arriving at DataReceived handler     *)


$wsConnected = {}; (* UUIDs from ClientConnected events             *)


$wsDisconnected = {}; (* UUIDs from ClientDisconnected events          *)


$wsServer =
	WebSocketServerStart[
		"HandlerFunctions" -> <|
			"DataReceived"       -> Function[
				a,
				AppendTo[$wsRxServer, a["Data"]]
			],
			"ClientConnected"    -> Function[
				a,
				AppendTo[$wsConnected, a["UUID"]]
			],
			"ClientDisconnected" -> Function[
				a,
				AppendTo[$wsDisconnected, a["UUID"]]
			]
		|>
	]


$wsTestPort = $wsServer["Port"]

(* ---- 5.1  Server lifecycle ---- *)
debug["Running: Int-01-ServerStart-ReturnsWebSocketObject ..."];
VerificationTest[
	Head[$wsServer],
	WebSocketObject,
	TestID -> "Int-01-ServerStart-ReturnsWebSocketObject"
]

debug["Running: Int-02-ServerType ..."];
VerificationTest[
	$wsServer["Type"],
	"WebSocketServer",
	TestID -> "Int-02-ServerType"
]

debug["Running: Int-03-ServerPort ..."];
VerificationTest[$wsServer["Port"], $wsTestPort, TestID -> "Int-03-ServerPort"]

debug["Running: Int-04-ServerTLS-DefaultFalse ..."];
VerificationTest[
	$wsServer["TLS"],
	False,
	TestID -> "Int-04-ServerTLS-DefaultFalse"
]

debug["Running: Int-05-ServerInGlobalRegistry ..."];
VerificationTest[
	MemberQ[$WebSocketServers, $wsServer],
	True,
	TestID -> "Int-05-ServerInGlobalRegistry"
]

(* ---- 5.2  Client connection ---- *)
$wsClient =
	WebSocketConnect[
		"ws://localhost:" <> ToString[$wsTestPort],
		"ReadTimeout" -> 2.0
	]

(* WebSocketConnect performs the HTTP upgrade synchronously; by the time it
   returns, the server has already processed the Upgrade request and fired
   ClientConnected.  No extra Pause needed for connection-phase assertions. *)
debug["Running: Int-06-ClientConnect-ReturnsWebSocketObject ..."];
VerificationTest[
	Head[$wsClient],
	WebSocketObject,
	TestID -> "Int-06-ClientConnect-ReturnsWebSocketObject"
]

debug["Running: Int-07-ClientType ..."];
VerificationTest[
	$wsClient["Type"],
	"WebSocketClient",
	TestID -> "Int-07-ClientType"
]

debug["Running: Int-08-ClientAddress ..."];
VerificationTest[
	$wsClient["Address"],
	"ws://localhost:" <> ToString[$wsTestPort],
	TestID -> "Int-08-ClientAddress"
]

debug["Running: Int-09-ClientInGlobalRegistry ..."];
VerificationTest[
	MemberQ[Values[$WebSocketClients], $wsClient],
	True,
	TestID -> "Int-09-ClientInGlobalRegistry"
]

debug["Running: Int-10-ClientConnected-HandlerFired ..."];
VerificationTest[
	Length[$wsConnected] >= 1,
	True,
	TestID -> "Int-10-ClientConnected-HandlerFired"
]

debug["Running: Int-11-Server-OneConnectedClient ..."];
VerificationTest[
	Length[$wsServer["ConnectedClients"]],
	1,
	TestID -> "Int-11-Server-OneConnectedClient"
]

(* ---- 5.3  Client → Server messaging ---- *)
$wsRxServer = {}

WriteString[$wsClient, "hello"]

Pause[0.25]

debug["Running: Int-12-ClientToServer-Text ..."];
VerificationTest[$wsRxServer, {"hello"}, TestID -> "Int-12-ClientToServer-Text"]

$wsRxServer = {}

BinaryWrite[$wsClient, ByteArray[{10, 20, 30}]]

Pause[0.25]

debug["Running: Int-13-ClientToServer-Binary ..."];
VerificationTest[
	First[$wsRxServer, $Failed],
	ByteArray[{10, 20, 30}],
	TestID -> "Int-13-ClientToServer-Binary"
]

(* JSON encoded as string (standard WebSocket convention) *)
$wsRxServer = {}

WriteString[$wsClient, ExportString[<|"n" -> 42|>, "RawJSON"]]

Pause[0.25]

debug["Running: Int-14-ClientToServer-JSON ..."];
VerificationTest[
	ImportString[First[$wsRxServer, "{}"], "RawJSON"],
	<|"n" -> 42|>,
	TestID -> "Int-14-ClientToServer-JSON"
]

(* Send three messages with 0.15 s gaps to prevent TCP frame coalescing;
   the server's SocketListen handler decodes one frame per event. *)
$wsRxServer = {}

WriteString[$wsClient, "a"]
Pause[0.15]

WriteString[$wsClient, "b"]
Pause[0.15]

WriteString[$wsClient, "c"]
Pause[0.25]

debug["Running: Int-15-ClientToServer-Sequential ..."];
VerificationTest[
	$wsRxServer,
	{"a", "b", "c"},
	TestID -> "Int-15-ClientToServer-Sequential"
]

(* ---- 5.4  Server → Client messaging ---- *)
$wsSrvConn = First[Values[$wsServer["ConnectedClients"]]]

$wsSrvConn["SendMessage"]["reply"]

Pause[0.15]

debug["Running: Int-16-ServerToClient-Text ..."];
VerificationTest[
	Read[$wsClient],
	"reply",
	TestID -> "Int-16-ServerToClient-Text"
]

(* Multiple server → client messages *)
$wsSrvConn["SendMessage"]["first"]
Pause[0.15]

$wsSrvConn["SendMessage"]["second"]

Pause[0.15]

debug["Running: Int-17-ServerToClient-Sequential-First ..."];
VerificationTest[
	Read[$wsClient],
	"first",
	TestID -> "Int-17-ServerToClient-Sequential-First"
]

debug["Running: Int-18-ServerToClient-Sequential-Second ..."];
VerificationTest[
	Read[$wsClient],
	"second",
	TestID -> "Int-18-ServerToClient-Sequential-Second"
]

(* ---- 5.5  Ping frame handling ---- *)
(* Client sends a raw Ping frame directly on the TCP socket
   (bypassing WebSocketObject so no extra framing is added).
   The server decodes it as "Ping" and forwards it to DataReceived;
   the server does not auto-respond — that is the current design. *)
$wsRxServer = {}

BinaryWrite[$wsClient["Socket"], WebSocketFrameCreate[Ping, Masking -> True]]

Pause[0.25]

debug["Running: Int-19-ServerReceivesPingFrame ..."];
VerificationTest[
	$wsRxServer,
	{"Ping"},
	TestID -> "Int-19-ServerReceivesPingFrame"
]

(* ---- 5.6  Disconnect & cleanup ---- *)
$wsDisconnected = {}

Close[$wsClient]

Pause[
	0.5
]; (* allow the server's SocketListen handler to process the Close frame *)

debug["Running: Int-20-ClientDisconnected-HandlerFired ..."];
VerificationTest[
	Length[$wsDisconnected] >= 1,
	True,
	TestID -> "Int-20-ClientDisconnected-HandlerFired"
]

debug["Running: Int-21-Server-ZeroClientsAfterClose ..."];
VerificationTest[
	Length[$wsServer["ConnectedClients"]],
	0,
	TestID -> "Int-21-Server-ZeroClientsAfterClose"
]

Close[$wsServer]

debug["Running: Int-22-ServerRemovedFromGlobalRegistry ..."];
VerificationTest[
	!MemberQ[$WebSocketServers, $wsServer],
	True,
	TestID -> "Int-22-ServerRemovedFromGlobalRegistry"
]
