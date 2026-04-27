BeginPackage["ToneAr`WebSocketLink`FileScope`Client`", {
	"ToneAr`WebSocketLink`",
	"ToneAr`WebSocketLink`Private`"
}];

Begin["`Private`"];


WebSocketConnect // Options = {
	"GUID" -> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11",
	"MaxStoredMessages" -> 1000,
	"VerifyPeer" -> True,
	"ReadTimeout" -> 5.,
	"ReadPollInterval" -> 0.01
};
WebSocketConnect[address_String, OptionsPattern[]] := Module[{
		server, upgradeRequest, handshakeResp, handshakeHeaders, messages, wsObj,
		parsedUrl, upgradeRequestString, sendMessage, waitForMessage, readMessage,
		getMessage, parsedPort, readBuffer = {},
		uuid = CreateUUID[],
		key = BaseEncode[
			ByteArray @ RandomInteger[255,16],
			"Base64"
		]
	},
	Enclose[
		parsedUrl =
			Confirm @ URLParse[
				Replace[
					StringReplace[address, {
						"ws://" -> "http://",
						"wss://" -> "https://"
					}],
					a_String?(Not @* StringContainsQ["://"]) :>
						If[StringStartsQ[Last[StringSplit[a, ":"]], "443"|"8443"],
							"https://",
							"http://"
						] <> a
			]
		];
		parsedPort = Replace[parsedUrl["Port"],
			None :> If[parsedUrl["Scheme"] === "https", 443, 80]
		];

		upgradeRequest = HTTPRequest[
			<|
				"Domain" -> parsedUrl["Domain"],
				"Scheme" -> parsedUrl["Scheme"],
				"Port" -> parsedPort,
				"Path" -> Replace[parsedUrl["Path"], {
					{} :> "/",
					p: {__String} :> StringRiffle[p, "/"]
				}],
				"Headers" -> <|
					"Upgrade" -> "websocket",
					"Connection" -> "upgrade",
					"Sec-WebSocket-Key" -> key,
					"Sec-WebSocket-Version" -> "13",
					"Sec-WebSocket-Protocol" -> "chat"
				|>
			|>
		];


		server = If[parsedUrl["Scheme"] === "https",
			With[{
					loopbackPort = Confirm[
						StartTLSClientProxy[
							parsedUrl["Domain"],
							parsedPort,
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
				SocketConnect[
					parsedUrl["Domain"] <> ":" <> ToString[parsedPort]
				],
				_SocketObject,
				StringTemplate["Failed to connect to WebSocket server at '``'."][address]
			]
		];

		upgradeRequestString = StringReplace[
			ExportString[upgradeRequest, "HTTPRequest"],
			LF -> CRLF
		];
		If[!StringEndsQ[upgradeRequestString, Repeated[CRLF, {2}]],
			upgradeRequestString = upgradeRequestString <> CRLF
		];
		WriteString[server, upgradeRequestString];

		With[{deadline = AbsoluteTime[] + OptionValue["ReadTimeout"]},
			While[!SocketReadyQ[server] && AbsoluteTime[] < deadline,
				Pause[OptionValue["ReadPollInterval"]]
			];
			ConfirmAssert[
				SocketReadyQ[server],
				StringTemplate[
					"Timed out waiting for WebSocket handshake response from '``'."
				][address]
			]
		];
		handshakeResp = ImportString[ReadString[server], "HTTPResponse"];

		handshakeHeaders = Association @ handshakeResp["Headers"];
		ConfirmAssert[
			StringMatchQ[handshakeHeaders["upgrade"],
				"websocket",
				IgnoreCase -> True
			],
			StringTemplate["Upgrade header '``' is incorrect."][
				handshakeHeaders["upgrade"]
			]
		];
		ConfirmAssert[
			StringMatchQ[handshakeHeaders["connection"],
				"Upgrade",
				IgnoreCase -> True
			],
			StringTemplate["Connection header '``' is incorrect."][
				handshakeHeaders["connection"]
			]
		];
		ConfirmAssert[
			StringMatchQ[handshakeHeaders["sec-websocket-accept"],
				Hash[key <> OptionValue["GUID"], "SHA1", "Base64Encoding"]
			],
			StringTemplate["Sec-WebSocket-Accept header '``' is incorrect."][
				handshakeHeaders["sec-websocket-accept"]
			]
		];

		messages = CreateDataStructure["RingBuffer", OptionValue["MaxStoredMessages"]];

		sendMessage[msg: (_String | _ByteArray)] :=
			BinaryWrite[server, WebSocketFrameCreate[msg, Masking -> True]];
		sendMessage[msg: (_Association | _List)] :=
			sendMessage[ ExportString[msg, "RawJSON"] ];
		sendMessage[msg_] :=
			sendMessage[ ToString @ msg ];

		waitForMessage[] := Module[{deadline},
			deadline = AbsoluteTime[] + OptionValue["ReadTimeout"];
			While[!SocketReadyQ[server] && AbsoluteTime[] < deadline,
				Pause[OptionValue["ReadPollInterval"]]
			];
			SocketReadyQ[server]
		];

		readMessage[] := Module[{frameByteCount, frameBytes},
			While[
				MissingQ[frameByteCount = webSocketFrameByteCount[readBuffer]],
				readBuffer = Join[readBuffer, BinaryReadList[server]]
			];
			frameBytes = Take[readBuffer, frameByteCount];
			readBuffer = Drop[readBuffer, frameByteCount];
			WebSocketFrameImport[ByteArray @ frameBytes]
		];

		getMessage[] := Module[{msg},
			If[messages["Length"] > 0,
				Return[messages["PopFront"]]
			];
			If[
				MissingQ[webSocketFrameByteCount[readBuffer]] &&
					!waitForMessage[],
				Return[Null]
			];
			msg = readMessage[];
			Which[
				msg === "Ping",
					BinaryWrite[server, WebSocketFrameCreate[Pong, Masking -> True]];
					getMessage[],
				msg === "Pong",
					getMessage[],
				True,
					msg
			]
		];

		(* Return a WebSocketObject *)
		wsObj = WebSocketObject[
			<|
				"Type"        -> "WebSocketClient",
				"UUID"        -> uuid,
				"Socket"      -> server,
				"Address"     -> address,
				"Messages"    -> messages,
				"GetMessage"  -> Function[{}, getMessage[]],
				"SendMessage" -> sendMessage
			|>
		];
		$WebSocketClients[uuid] = wsObj;
		wsObj
		,
		(* OnError *)
		Function[er,
			Quiet @ Close[server];
			er
		]
	]
];


End[];
EndPackage[];
