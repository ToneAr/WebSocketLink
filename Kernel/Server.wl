BeginPackage["WSLink`", {
	"WSLink`PackageScope`",
	"WSLink`"
}];


Begin["`Private`"];

testFunction[] := Print[bitListToInt[{1,0,1}]];

WSServerStart // ClearAll;
WSServerStart // Options = {
	"GUID" -> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
};
WSServerStart[port_Integer : Automatic] := Module[{ listenerFunction },
	listenerFunction = Function[assoc,
		Module[{
				request,headers,key,acceptKey,response,isUpgradeRequest,
				guid = OptionValue["GUID"],
				client = assoc["SourceSocket"]
			},

			request = Quiet[ImportString[assoc["Data"],"HTTPRequest"]];
			headers = request["Headers"];

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

			(* Check if it's a WebSocket upgrade request *)
			If[ isUpgradeRequest,
				
				(* WebSocket handshake *)
				key = Lookup[headers, "sec-websocket-key",""];
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
				(* Store client for future communication *)
				AppendTo[$WebSocketClients, <|
					"Socket" -> client,
					"Queue" -> CreateDataStructure["Queue"],
					"GetMessage" -> Function[
						SelectFirst[$WebSocketClients,
							StringMatchQ[#Socket["UUID"], client["UUID"]] &
						]["Queue"]["Pop"]
					]
				|>],
			(* Else *)
				(* Select Queue associated with client *)
				SelectFirst[$WebSocketClients,
					StringMatchQ[#Socket["UUID"], client["UUID"]] &
				]["Queue"][
					(* Push message onto the queue *)
					"Push", importWebSocketFrame[ByteArray @ assoc["DataBytes"]]
				];
				(* :!CodeAnalysis::BeginBlock:: *)
				(* :!CodeAnalysis::Disable::SuspiciousSessionSymbol:: *)
				Echo["New message from: "<>client["UUID"]];
				(* :!CodeAnalysis::EndBlock:: *)
			]
		]
	];
	SocketListen[port, listenerFunction]
];

End[];
EndPackage[];

