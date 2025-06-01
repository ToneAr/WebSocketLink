(* :!CodeAnalysis::BeginBlock:: *)
(* :!CodeAnalysis::Disable::SuspiciousSessionSymbol:: *)
BeginPackage["ToneAr`WebSocketLink`", {
	"ToneAr`WebSocketLink`Private`"
}];
Begin["`FileScope`Server`Private`"];


(* -----------------------WebSocketServerStart------------------------------
 * Description:  Start a WebSocket listener server
 * Return:       _Association (* WebSocketObject *)
 *)
WebSocketServerStart // Clear;
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

	If[OptionValue[OverwriteTarget],
		Quiet @ Close @ SelectFirst[$WebSocketServers, Function[wso,
			wso["Port"] === port
		]]
	];

	listenerFunction = Function[assoc,
		Module[{
				request,headers,key,acceptKey,response,isUpgradeRequest,
				getMessage, sendMessage, extBuffer, wsAssoc,
				guid = OptionValue["GUID"],
				client = assoc["SourceSocket"]
			},
			Enclose[
				request = Quiet[ImportString[assoc["Data"],"HTTPRequest"]];
				headers = request["Headers"];
				(* Check if it's a WebSocket UPGRADE request *)
				isUpgradeRequest = Quiet @ TrueQ[
					And[
						StringContainsQ[
							Lookup[headers, "connection", ""],
							"upgrade",
							IgnoreCase->True
						],
						StringContainsQ[
							Lookup[headers, "upgrade", ""],
							"websocket",
							IgnoreCase->True
						]
					]
				];
				If[ isUpgradeRequest,
				(* Initial client setup *)
					(* Create message buffer *)
					extBuffer = Confirm[
						CreateDataStructure["RingBuffer", 100],
						"Failed to create RingBuffer"
					];
					(* WebSocket handshake *)
					key = Confirm[
						Lookup[headers, "sec-websocket-key", $Failed],
						"Failed to find sec-websocket-key"
					];
					acceptKey = Confirm[
						Hash[key <> guid, "SHA1", "Base64Encoding"],
						"Failed to create accept key"
					];
					(* Send handshake response *)
					ConfirmMatch[
						response = ExportString[
							HTTPResponse["",<|
								"StatusCode" -> 101,
								"Headers" -> {
									"Upgrade" -> "websocket",
									"Connection" -> "Upgrade",
									"Sec-WebSocket-Accept" -> acceptKey
								}
							|>],
							"HTTPResponse"
						],
						_String,
						"Failed to create handshake response"
					];
					Confirm[
						WriteString[client, response],
						"Failed to send handshake response"
					];
					(* Define message handling functions *)
					getMessage[] := extBuffer["PopBack"];
					sendMessage[ msg: (_Association | _List) ] := sendMessage[
						ExportString[msg, "RawJSON"]
					];
					sendMessage[ msg_ ] := sendMessage[
						ToString @ msg
					];
					sendMessage[ msg_String ] := BinaryWrite[client,
						WebSocketFrameCreate[ msg ]
					];
					(* Store client for future communication *)
					wsAssoc = <|
						"Type" -> "WebSocketClientConnection",
						"UUID" -> client["UUID"],
						"Socket" -> client,
						"Messages" -> extBuffer,
						"GetMessage" :> getMessage[],
						"SendMessage" :> sendMessage
					|>;
					(* Store client in global variable *)
					Confirm[
						connectedClients[client["UUID"]] = WebSocketObject @ wsAssoc,
						"Failed to store client"
					];
					OptionValue["HandlerFunctions"]["ClientConnected"] @ <|
						assoc,
						wsAssoc
					|>;
					debugPrint["Successful connection to: " <> client["UUID"]];
					,
				(* Else - Import WebSocket frame *)
					With[{
							data = WebSocketFrameImport[
								ByteArray @ assoc["DataBytes"]
							],
							wsClientObj = connectedClients[client["UUID"]]
						},
						(* If receiving a CLOSE frame, purge connection to client *)
						If[MatchQ[data, Null],
							debugPrint["Closing connection to: " <> client["UUID"]];
							connectedClients =
								KeyDrop[connectedClients,
									client["UUID"]
								];
							OptionValue["HandlerFunctions"]["ClientDisconnected"] @ <|
								assoc,
								Normal @ wsClientObj,
								"Data" -> Null
							|>;
							Close[client];
							Return[]
						];
						(* Handle Messages *)
						debugPrint["New message from: " <> client["UUID"]];
						wsClientObj["Messages"][
							"PushBack", data
						];
						OptionValue["HandlerFunctions"]["DataReceived"] @ <|
							assoc,
							Normal @ wsClientObj,
							"Data" -> data
						|>;
					];
				]
			]
		]
	];

	listener = SocketListen[port, listenerFunction];
	serverObj = <|
		"Type"     -> "WebSocketServer",
		"Listener" -> listener,
		"Socket"   -> listener["Socket"],
		"UUID"     -> serverUUID,
		"Port"     -> listener["Socket"]["DestinationPort"],
		"ConnectedClients" :> connectedClients,
		"HandlerFunctions" -> OptionValue["HandlerFunctions"]
	|>;
	server = WebSocketObject[serverObj];
	AppendTo[$WebSocketServers, server];
	server
];


End[];
EndPackage[];
(* :!CodeAnalysis::EndBlock:: *)
