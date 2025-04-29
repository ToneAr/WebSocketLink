(* :!CodeAnalysis::BeginBlock:: *)
(* :!CodeAnalysis::Disable::SuspiciousSessionSymbol:: *)
BeginPackage["WebSocketLink`Server`", {
	"WebSocketLink`",
	"WebSocketLink`PackageScope`"
}];


Begin["`Private`"];

(* -----------------------WebSocketServerStart------------------------------
 * Description:  Start a WebSocket listener server
 * Return:       _Association (* WebSocketObject *)
 *)
WebSocketServerStart // Clear;
WebSocketServerStart // Options = {
	"GUID" -> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11",
	"HandlerFunctions" -> <|
		"DataReceived" -> Identity,
		"Connected"    -> Identity,
		"Disconnected" -> Identity
	|>
};
WebSocketServerStart[port_Integer : Automatic, OptionsPattern[]] := Module[{
		listenerFunction, listener, serverObj, connectedClients = <||>,
		serverUUID = CreateUUID[]
	},
	listenerFunction = Function[assoc,
		Module[{
				request,headers,key,acceptKey,response,isUpgradeRequest,
				getMessage, sendMessage, extVector, 
				guid = OptionValue["GUID"],
				client = assoc["SourceSocket"]
			},
			Echo @ assoc;
			request = Quiet[ImportString[assoc["Data"],"HTTPRequest"]];
			headers =  request["Headers"];

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

			(* Check if it's a WebSocket UPGRADE request *)
			If[ isUpgradeRequest,
				(* Create message vector *)
				extVector = CreateDataStructure["RingBuffer", 100];
				(* WebSocket handshake *)
				key = Lookup[headers, "sec-websocket-key", ""];
				acceptKey = Hash[key <> guid, "SHA1", "Base64Encoding"];
				(* Send handshake response *)
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
				];
				WriteString[client, response];
				(* Define message handling functions *)
				getMessage[ num_Integer: -1 ] := extVector["Part", num];
				sendMessage[ msg_String ] := BinaryWrite[client,
					WebSocketFrameCreate[ msg ]
				];
				sendMessage[ msg: (_Association | _List) ] := sendMessage[
					ExportString[msg, "RawJSON"]
				];
				sendMessage[ msg_ ] := sendMessage[
					ToString @ msg
				];
				(* Store client for future communication *)
				connectedClients[client["UUID"] ] = <|
					"Socket" -> client,
					"Messages" -> extVector,
					"GetMessage" :> getMessage,
					"SendMessage" :> sendMessage
				|>;
				OptionValue["HandlerFunctions"]["Connected"] @ assoc;
				Print["Successful connection to: " <> client["UUID"]];
				,
			(* Else - Import WebSocket frame *)
				With[{
						data = WebSocketFrameImport[
							ByteArray @ assoc["DataBytes"]
						]
					},
					(* If receiving a closing frame, purge connection to client *)
					If[MatchQ[data, Null],
						Print["Closing connection to: " <> client["UUID"]];
						connectedClients =
							KeyDrop[connectedClients,
								client["UUID"]
							];
						Close[client];
						Return[]
					];
					(* Handle Messages *)
					OptionValue["HandlerFunctions"]["DataReceived"] @ <|
						assoc,
						"Data" -> data
					|>;
					connectedClients[client["UUID"]]["Messages"][
						"PushBack", data
					]
				];
				Print["New message from: " <> client["UUID"]];
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
	AppendTo[$WebSocketServers, serverObj];
	WebSocketObject[serverObj]
];


End[];
EndPackage[];
(* :!CodeAnalysis::EndBlock:: *)