BeginPackage["ToneAr`WebSocketLink`", {"ToneAr`WebSocketLink`Private`"}];

Begin["`FileScope`Client`Private`"];


WebSocketConnect // Options =
	{
		"GUID"               -> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11",
		"MaxStoredMessages"  -> 1000,
		"VerifyPeer"         -> True,
		"ReadTimeout"        -> 5.,
		"ReadPollInterval"   -> 0.01,
		HandlerFunctions     -> <|"DataReceived" -> Identity|>,
		HandlerFunctionsKeys -> Automatic
	};
WebSocketConnect[address_String, OptionsPattern[]] :=
	Module[{
			server,
			upgradeRequest,
			handshakeResp,
			handshakeHeaders,
			messages,
			wsObj,
			parsedUrl,
			upgradeRequestString,
			sendMessage,
			dispatchBufferedFrames,
			listenerFunction,
			readHandshakeResponse,
			getMessage,
			handlerFunctions,
			dataReceivedHandler,
			connectionOpenQ = True,
			parsedPort,
			readBuffer = {},
			uuid = CreateUUID[],
			key = BaseEncode[ByteArray @ RandomInteger[255, 16], "Base64"]
		},
		Enclose[
			readHandshakeResponse[] :=
				Module[{
						bytes = {},
						chunk,
						headerByteCount = Missing["Incomplete"],
						deadline
					},
					deadline = AbsoluteTime[] + OptionValue["ReadTimeout"];
					While[
						MissingQ[headerByteCount] && AbsoluteTime[] < deadline,
						If[SocketReadyQ[server], chunk = BinaryReadList[server];
						If[Length[chunk] > 0, bytes = Join[bytes, chunk];
						headerByteCount =
							Replace[
								SequencePosition[bytes, {13, 10, 13, 10}, 1],
								{{{_, end_}} :> end, _ :> Missing["Incomplete"]}
							], Pause[OptionValue["ReadPollInterval"]]], Pause[OptionValue["ReadPollInterval"]]]
					];
					ConfirmAssert[
						!MissingQ[headerByteCount],
						StringTemplate[
							StringJoin[
								"Timed out waiting for WebSocket ",
								"handshake response from '``'."
							]
						][
							address
						]
					];
					readBuffer = Drop[bytes, headerByteCount];
					ByteArrayToString[
						ByteArray @ Take[bytes, headerByteCount],
						"UTF-8"
					]
				];
			parsedUrl =
				Confirm @
				URLParse[
					Replace[
						StringReplace[
							address,
							{"ws://" -> "http://", "wss://" -> "https://"}
						],
						a_String?(Not @* StringContainsQ["://"]) :> If[
							StringStartsQ[
								Last[StringSplit[a, ":"]],
								"443" | "8443"
							],
							"https://",
							"http://"
						] <>
						a
					]
				];
			parsedPort =
				Replace[
					parsedUrl["Port"],
					None :> If[parsedUrl["Scheme"] === "https", 443, 80]
				];
			upgradeRequest =
				HTTPRequest[
					<|
						"Domain"  -> parsedUrl["Domain"],
						"Scheme"  -> parsedUrl["Scheme"],
						"Port"    -> parsedPort,
						"Path"    -> Replace[
							parsedUrl["Path"],
							{{} :> "/", p : {__String} :> StringRiffle[p, "/"]}
						],
						"Headers" -> <|
							"Upgrade"                -> "websocket",
							"Connection"             -> "upgrade",
							"Sec-WebSocket-Key"      -> key,
							"Sec-WebSocket-Version"  -> "13",
							"Sec-WebSocket-Protocol" -> "chat"
						|>
					|>
				];
			server = If[parsedUrl["Scheme"] === "https", With[{
						loopbackPort =
							Confirm[
								StartTLSClientProxy[
									parsedUrl["Domain"],
									parsedPort,
									Automatic,
									OptionValue["VerifyPeer"]
								],
								StringTemplate[
									StringJoin[
										"Failed to start TLS proxy ",
										"for '``'."
									]
								][
									address
								]
							]
					},
					ConfirmMatch[
						SocketConnect["localhost:" <> ToString[loopbackPort]],
						_SocketObject,
						StringTemplate[
							StringJoin[
								"Failed to connect loopback socket ",
								"for '``'."
							]
						][
							address
						]
					]
				], ConfirmMatch[SocketConnect[parsedUrl["Domain"] <> ":" <> ToString[parsedPort]], _SocketObject, StringTemplate["Failed to connect to WebSocket server at '``'."][address]]];
			upgradeRequestString =
				StringReplace[
					ExportString[upgradeRequest, "HTTPRequest"],
					LF -> CRLF
				];
			If[!StringEndsQ[upgradeRequestString, Repeated[CRLF, {2}]],
				upgradeRequestString = upgradeRequestString <> CRLF
			];
			WriteString[server, upgradeRequestString];
			handshakeResp =
				ImportString[readHandshakeResponse[], "HTTPResponse"];
			handshakeHeaders = Association @ handshakeResp["Headers"];
			ConfirmAssert[
				StringMatchQ[
					handshakeHeaders["upgrade"],
					"websocket",
					IgnoreCase -> True
				],
				StringTemplate["Upgrade header '``' is incorrect."][
					handshakeHeaders["upgrade"]
				]
			];
			ConfirmAssert[
				StringMatchQ[
					handshakeHeaders["connection"],
					"Upgrade",
					IgnoreCase -> True
				],
				StringTemplate["Connection header '``' is incorrect."][
					handshakeHeaders["connection"]
				]
			];
			ConfirmAssert[
				StringMatchQ[
					handshakeHeaders["sec-websocket-accept"],
					Hash[key <> OptionValue["GUID"], "SHA1", "Base64Encoding"]
				],
				StringTemplate[
					"Sec-WebSocket-Accept header '``' is incorrect."
				][
					handshakeHeaders["sec-websocket-accept"]
				]
			];
			messages =
				CreateDataStructure[
					"RingBuffer",
					OptionValue["MaxStoredMessages"]
				];
			sendMessage[msg : (_String | _ByteArray)] :=
				BinaryWrite[server, WebSocketFrameCreate[msg, Masking -> True]];
			sendMessage[msg : (_Association | _List)] :=
				sendMessage[ExportString[msg, "RawJSON"]];
			sendMessage[msg_] := sendMessage[ToString @ msg];
			handlerFunctions =
				Replace[
					OptionValue[HandlerFunctions],
					Except[_Association] -> <||>
				];
			dataReceivedHandler =
				Lookup[handlerFunctions, "DataReceived", Identity];
			dispatchBufferedFrames[event_Association : <||>] :=
				Module[{frameByteCount, frameBytes, msg},
					While[
						!MissingQ[
							frameByteCount = webSocketFrameByteCount[readBuffer]
						],
						{frameBytes, readBuffer} =
							TakeDrop[readBuffer, frameByteCount];
						msg = WebSocketFrameImport[ByteArray @ frameBytes];
						Switch[msg,
							Null,
								connectionOpenQ = False;
								Quiet @ Close[server];
								Return[], "Ping", BinaryWrite[
									server,
									WebSocketFrameCreate[Pong, Masking -> True]
								],
							"Pong",
								Null,
							_,
								messages["PushBack", msg];
								dataReceivedHandler @
								Join[
									event,
									<|
										"SourceSocket"    -> Lookup[
											event,
											"SourceSocket",
											server
										],
										"Data"            -> msg,
										"DataBytes"       -> frameBytes,
										"DataByteArray"   -> ByteArray @ frameBytes,
										"SendMessage"     -> sendMessage,
										"WebSocketObject" -> wsObj
									|>
								]
						]
					]
				];
			listenerFunction =
				Function[
					event,
					Module[{socketBytes},
						socketBytes =
							Replace[
								Lookup[event, "DataBytes", Missing[]],
								_Missing :> Replace[
									Lookup[event, "DataByteArray", Missing[]],
									{bytes_ByteArray :> Normal[bytes], _ :> {}}
								]
							];
						If[ListQ[socketBytes] && Length[socketBytes] > 0,
							readBuffer = Join[readBuffer, socketBytes];
							dispatchBufferedFrames[event]
						]
					]
				];
			getMessage[] :=
				Module[{deadline},
					If[messages["Length"] > 0, Return[messages["PopFront"]]];
					deadline = AbsoluteTime[] + OptionValue["ReadTimeout"];
					While[
						connectionOpenQ &&
						messages["Length"] == 0 &&
						AbsoluteTime[] < deadline,
						Pause[OptionValue["ReadPollInterval"]]
					];
					If[messages["Length"] > 0, messages["PopFront"], Null]
				];
			(* Return a WebSocketObject *)
			wsObj =
				WebSocketObject[
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
			SocketListen[
				server,
				listenerFunction,
				HandlerFunctionsKeys -> OptionValue[HandlerFunctionsKeys]
			];
			dispatchBufferedFrames[<|"SourceSocket" -> server|>];
			wsObj,
			(* OnError *)
			Function[
				er,
				Quiet @ Close[server];
				er
			]
		]
	];


End[];
EndPackage[];
