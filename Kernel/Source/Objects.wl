BeginPackage["ToneAr`WebSocketLink`FileScope`Objects`", {
	"ToneAr`WebSocketLink`",
	"ToneAr`WebSocketLink`Private`"
}];
Begin["`Private`"];

serverKeys = {
	"Type",
	"Listener",
	"Socket",
	"UUID",
	"Port",
	"ConnectedClients",
	"HandlerFunctions"
};
connectedClientKeys = {
	"Type",
	"UUID",
	"Socket",
	"Messages",
	"GetMessage",
	"SendMessage"
};
clientKeys = {
	"Type",
	"UUID",
	"Socket",
	"Address",
	"Messages",
	"GetMessage",
	"SendMessage"
};

$icon = Import[
	PacletObject["ToneAr/WebSocketLink"]["AssetLocation", "logo.svg"],
	"Graphics"
];


webSocketObjectQ = Function[asc, Or[
	AllTrue[serverKeys, KeyExistsQ[asc, #]&],
	AllTrue[connectedClientKeys, KeyExistsQ[asc, #]&],
	AllTrue[clientKeys, KeyExistsQ[asc, #]&]
]];


WebSocketObject /: MakeBoxes[
		obj:( WebSocketObject[asc: _Association]),
		form: (StandardForm | TraditionalForm )
	] := Module[{above, below},
		above = Switch[asc["Type"],
			"WebSocketServer",
			{
				{BoxForm`SummaryItem[{"Type: ", asc["Type"]}]},
				{BoxForm`SummaryItem[{"UUID: ", asc["UUID"]}]},
				{BoxForm`SummaryItem[{"Local Port: ", asc["Port"]}]},
				{BoxForm`SummaryItem[{"Clients connected: ",
					Dynamic[
						If[FailureQ @ asc["Socket"]["InprocQ"],
							$WebSocketServers = Select[$WebSocketServers,
								(#["UUID"] =!= asc["UUID"])&
							];
							"Inactive",
							Length[asc["ConnectedClients"]]
						]
					]
				}]}
			},
			"WebSocketClientConnection",
			{
				{BoxForm`SummaryItem[{"Type: ", asc["Type"]}]},
				{BoxForm`SummaryItem[{"UUID: ", asc["UUID"]}]},
				{BoxForm`SummaryItem[{"Messages: ",
					Dynamic[ asc["Messages"]["Length"] ]
				}]}
			},
			"WebSocketClient",
			{
				{BoxForm`SummaryItem[{"Type: ", asc["Type"]}]},
				{BoxForm`SummaryItem[{"UUID: ", asc["UUID"]}]},
				{BoxForm`SummaryItem[{"Address: ", asc["Address"]}]},
				{BoxForm`SummaryItem[{"Messages: ",
					Dynamic[asc["Messages"]["Length"]]
				}]}
			}
		];
		below = Switch[asc["Type"],
			"WebSocketServer",
			{
				BoxForm`SummaryItem[{"Socket: ",   asc["Socket"]}],
				BoxForm`SummaryItem[{"Listener: ", asc["Listener"]}]
			},
			"WebSocketClientConnection",
			{
				BoxForm`SummaryItem[{"Socket: ",   asc["Socket"]}],
				BoxForm`SummaryItem[{"Messages: ", asc["Messages"]}]
			},
			"WebSocketClient",
			{

			}
		];

		BoxForm`ArrangeSummaryBox[
			WebSocketObject, (* head *)
			obj,      (* interpretation *)
			$icon,
			above,    (* always shown content *)
			below,    (* expandable content *)
			form,
			"Interpretable" -> Automatic
		]
	];

WebSocketObject[asc: _Association?webSocketObjectQ][prop_] :=
	Lookup[asc, prop, Missing["NotFound", prop]];
WebSocketObject[asc: _Association?webSocketObjectQ]["Properties"] :=
	Keys[asc];

WebSocketObject /: (Close|DeleteObject)[
	WebSocketObject[assoc : _Association?webSocketObjectQ]
] := (
	Switch[assoc["Type"],
		"WebSocketClient",
			BinaryWrite[assoc["Socket"], WebSocketFrameCreate[Close]],
		"WebSocketServer",
			$WebSocketServers = Select[$WebSocketServers, Function[wso,
				wso["UUID"] =!= assoc["UUID"]
			]];
			If[TrueQ[assoc["TLS"]] && assoc["SSLServerSocket"] =!= None,
				Quiet[assoc["SSLServerSocket"]@close[]]
			];
	];
	Close @ assoc["Socket"]
);

WebSocketObject /: WriteString[
	wso: WebSocketObject[assoc : _Association?webSocketObjectQ],
	data_String
] := Enclose[
	ConfirmAssert[StringContainsQ[assoc["Type"], "WebSocketClient"],
		"Cannot write to a WebSocketServer object."
	];
	wso["SendMessage"][data];
];
WebSocketObject /: BinaryWrite[
	wso: WebSocketObject[assoc : _Association?webSocketObjectQ],
	data_ByteArray
] := Enclose[
	ConfirmAssert[StringContainsQ[assoc["Type"], "WebSocketClient"],
		"Cannot write to a WebSocketServer object."
	];
	wso["SendMessage"][data];
];
WebSocketObject /: (ReadString|Read)[
	wso: WebSocketObject[assoc : _Association?webSocketObjectQ]
] := Enclose[
	ConfirmAssert[StringContainsQ[assoc["Type"], "WebSocketClient"],
		"Cannot read from a WebSocketServer object."
	];
	wso["GetMessage"]
];

WebSocketObject /: Normal[obj : WebSocketObject[asc: _Association?webSocketObjectQ]] := asc;


End[];
EndPackage[];
