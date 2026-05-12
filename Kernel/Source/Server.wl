(* :!CodeAnalysis::BeginBlock:: *)
(* :!CodeAnalysis::Disable::SuspiciousSessionSymbol:: *)
BeginPackage["ToneAr`WebSocketLink`", {"ToneAr`WebSocketLink`Private`"}];

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
		clientBuffers = <||>,
		serverUUID = CreateUUID[],
		sslServerSocket = None,
		listenPort
	},
	Enclose[
		listenPort = port;
		If[TrueQ @ OptionValue["TLS"],
			With[{
					certConfig = Replace[OptionValue["Certificate"], {
						p_String /; OptionValue["CertificatePassword"] =!= "" :>
							{p, OptionValue["CertificatePassword"]}
					}]
				},
				{sslServerSocket, listenPort} = Confirm[
					StartTLSServerProxy[port, certConfig],
					"Failed to start TLS server proxy"
				]
			]
		];

		If[OptionValue[OverwriteTarget] && IntegerQ[listenPort],
			With[{
					existingSocket = SelectFirst[Sockets[], Function[wso,
						wso["DestinationPort"] === listenPort
					]]
				},
				If[!MissingQ[existingSocket],
					Quiet[Close[existingSocket]]
				]
			]
		];

		listenerFunction = Function[assoc,
			Module[{
					request,headers,key,acceptKey,response,isUpgradeRequest,
					getMessage, sendMessage, extBuffer, wsAssoc,
					clientUUID, data, frameByteCount, frameBytes, wsClientObj,
					guid = OptionValue["GUID"],
					client = assoc["SourceSocket"]
				},
				Enclose[
					clientUUID = client["UUID"];
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
						sendMessage[ msg_Association] := sendMessage[
							ExportString[msg, "RawJSON"]
						];
						sendMessage[ msg: Except[ (_Association | _List | _String) ] ] := sendMessage[
							ToString @ msg
						];
						sendMessage[ msg_String ] := BinaryWrite[client,
							WebSocketFrameCreate[ msg ]
						];
						(* Store client for future communication *)
						wsAssoc = <|
							"Type" -> "WebSocketClientConnection",
							"UUID" -> clientUUID,
							"Socket" -> client,
							"Messages" -> extBuffer,
							"GetMessage" -> Function[{}, getMessage[]],
							"SendMessage" -> sendMessage
						|>;
						(* Store client in global variable *)
						Confirm[
							connectedClients[clientUUID] = WebSocketObject @ wsAssoc,
							"Failed to store client"
						];
						clientBuffers[clientUUID] = {};
						OptionValue["HandlerFunctions"]["ClientConnected"] @ <|
							assoc,
							wsAssoc
						|>;
						debugPrint["Successful connection to: " <> clientUUID];
						,
					(* Else - Import WebSocket frame *)
						wsClientObj = Lookup[
							connectedClients,
							clientUUID,
							Missing["NotConnected"]
						];
						If[MissingQ[wsClientObj],
							Return[]
						];
						clientBuffers[clientUUID] = Join[
							Lookup[clientBuffers, clientUUID, {}],
							assoc["DataBytes"]
						];
						While[
							!MissingQ[
								frameByteCount =
									webSocketFrameByteCount[clientBuffers[clientUUID]]
							],
							frameBytes = Take[
								clientBuffers[clientUUID],
								frameByteCount
							];
							clientBuffers[clientUUID] = Drop[
								clientBuffers[clientUUID],
								frameByteCount
							];
							data = WebSocketFrameImport[ByteArray @ frameBytes];
							(* If receiving a CLOSE frame, purge connection to client *)
							If[MatchQ[data, Null],
								debugPrint["Closing connection to: " <> clientUUID];
								connectedClients =
									KeyDrop[connectedClients,
										clientUUID
									];
								clientBuffers =
									KeyDrop[clientBuffers,
										clientUUID
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
							debugPrint["New message from: " <> clientUUID];
							wsClientObj["Messages"][
								"PushBack", data
							];
							OptionValue["HandlerFunctions"]["DataReceived"] @ <|
								assoc,
								Normal @ wsClientObj,
								"Data" -> data
							|>;
						]
					]
				]
			]
		];

		listener = Confirm @ SocketListen[listenPort, listenerFunction];


		serverObj = <|
			"Type"     -> "WebSocketServer",
			"Listener" -> listener,
			"Socket"   -> listener["Socket"],
			"UUID"     -> serverUUID,
			"TLS"      -> TrueQ @ OptionValue["TLS"],
			"Port"     -> If[TrueQ @ OptionValue["TLS"],
				port,
				listener["Socket"]["DestinationPort"]
			],
			"SSLServerSocket"  -> sslServerSocket,
			"ConnectedClients" -> Function[{}, connectedClients],
			"HandlerFunctions" -> OptionValue["HandlerFunctions"]
		|>;
		server = WebSocketObject[serverObj];
		AppendTo[$WebSocketServers, server];
		server
	]
];
(* :!CodeAnalysis::EndBlock:: *)

End[];
EndPackage[];
