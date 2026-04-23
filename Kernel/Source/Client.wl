BeginPackage["ToneAr`WebSocketLink`FileScope`Client`", {
	"ToneAr`WebSocketLink`",
	"ToneAr`WebSocketLink`Private`"
}];

Begin["`Private`"];


WebSocketConnect // Options = {
	"GUID" -> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11",
	"MaxStoredMessages" -> 1000,
	"VerifyPeer" -> True
};
WebSocketConnect[address_String, OptionsPattern[]] := Module[{
		server, upgradeRequest, handshakeResp, handshakeHeaders, messages,
		parsedUrl, upgradeRequestString, sendMessage,
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

		upgradeRequest = HTTPRequest[
			<|
				"Domain" -> parsedUrl["Domain"],
				"Scheme" -> parsedUrl["Scheme"],
				"Port" -> Replace[parsedUrl["Port"],
					None :> If[parsedUrl["Scheme"] === "https", 443, 80]
				],
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

		upgradeRequestString = StringReplace[
			ExportString[upgradeRequest, "HTTPRequest"],
			LF -> CRLF
		];
		If[!StringEndsQ[upgradeRequestString, Repeated[CRLF, {2}]],
			upgradeRequestString = upgradeRequestString <> CRLF
		];
		WriteString[server, upgradeRequestString];

		While[!SocketReadyQ[server],
			Pause[0.00001]
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

		(* Return a WebSocketObject *)
		WebSocketObject[
			<|
				"Type"    -> "WebSocketClient",
				"UUID"    -> uuid["UUID"],
				"Socket"  -> server,
				"Address" -> address,
				"Messages" -> messages,
				"GetMessage" :> If[SocketReadyQ[server],
					WebSocketFrameImport[ByteArray @* BinaryReadList @ server],
					Null
				],
				"SendMessage" :> sendMessage
			|>
		]
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
