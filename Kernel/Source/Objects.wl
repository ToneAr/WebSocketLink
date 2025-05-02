BeginPackage["TonyAristeidou`WebSocketLink`Objects`", {
	"TonyAristeidou`WebSocketLink`",
	"TonyAristeidou`WebSocketLink`PackageScope`"
}];

Begin["`Private`"];

serverKeys = {
	"Type", "Listener", "Socket", "UUID",
	"Port", "ConnectedClients", "HandlerFunctions"
};
connectedClientKeys = {
	"Type", "UUID", "Socket", "Messages", "GetMessage", "SendMessage"
}

$icon = Graphics[
	GeometricTransformation[{Thickness[0.00125], FaceForm[
	{RGBColor[0, 0, 0], Opacity[1.]}], FilledCurve[{{{0, 2, 0}, {0, 1, 0}, {0, 1, 0}, {0, 
	1, 0}, {0, 1, 0}, {0, 1, 0}}, {{0, 2, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1,
	 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 0},
	 {0, 1, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 0}, {0,
	 1, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1,
	 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 0}, {0, 1, 0},
	 {0, 1, 0}, {0, 1, 0}}}, {{{192.44021606445312, 144.6446075439453}, {
	224.22010803222656, 144.6446075439453}, {224.22010803222656, 68.33934020996094
	}, {188.4153289794922, 32.5345573425293}, {165.94300842285156, 55.00687789916992
	}, {192.44021606445312, 81.50409698486328}, {192.44021606445312, 144.6446075439453
	}}, {{224.30397033691406, 160.57647705078125}, {178.01768493652344, 160.57647705078125
	}, {113.45169067382812, 160.57647705078125}, {86.9544677734375, 134.0792694091797
	}, {98.19063568115234, 122.84310150146484}, {120.07598876953125, 144.7284698486328
	}, {165.1044921875, 144.7284698486328}, {120.7468032836914, 100.28693389892578
	}, {132.0668182373047, 88.9669189453125}, {176.42449951171875, 133.32460021972656
	}, {176.42449951171875, 88.29610443115234}, {154.6230010986328, 66.49459838867188
	}, {165.77529907226562, 55.34228515625}, {110.6845703125, 0.}, {56.3485107421875,
	 0.}, {0., 0.}, {31.69603729248047, 31.69603729248047}, {31.69603729248047,
	 31.779888153076172}, {31.863740921020508, 31.779888153076172}, {97.43596649169922,
	 31.779888153076172}, {120.66295623779297, 55.00687789916992}, {86.70291900634766,
	 88.9669189453125}, {63.47592544555664, 65.73992919921875}, {63.47592544555664,
	 47.71175765991211}, {31.69603729248047, 47.71175765991211}, {31.69603729248047,
	 78.9046859741211}, {86.70291900634766, 133.91156005859375}, {64.31444549560547,
	 156.30003356933594}, {100.11922454833984, 192.1048126220703}, {154.45529174804688,
	 192.1048126220703}, {256., 192.1048126220703}, {224.30397033691406, 
	160.57647705078125}}}]}, {{{{3.09066963031484, 0.}, {0., -3.238526743538177
	}}, {-0.8058135843668452, -19.339526024804655}}}], AspectRatio -> 0.827930174563591,
	 ImagePadding -> {{0., 0.}, {0., 0.}}, ImageSize -> {40.1, 33.2},
	 PlotRange -> {{0., 800.}, {-657.4257425742571, 0.}},
	 PlotRangePadding -> None
];

webSocketObjectQ = Function[asc, Or[
	AllTrue[serverKeys, KeyExistsQ[asc, #]&],
	AllTrue[connectedClientKeys, KeyExistsQ[asc, #]&]
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
								Function[wso,
									wso["UUID"] =!= asc["UUID"]
								]
							];
							"Inactive",
							Length[asc["ConnectedClients"]]
						],
						TrackedSymbols :> {asc["Socket"]}
					]
				}]}
			},
			"WebSocketClientConnection",
			{
				{BoxForm`SummaryItem[{"Type: ", asc["Type"]}]},
				{BoxForm`SummaryItem[{"UUID: ", asc["UUID"]}]},
				{BoxForm`SummaryItem[{"Messages: ",
					Dynamic[asc["Messages"]["Length"],
						TrackedSymbols :> { asc["Messages"] }
					]
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
	dep:WebSocketObject[assoc : _Association?webSocketObjectQ]
] := (
	$WebSocketServers = Select[$WebSocketServers, Function[wso,
		wso["UUID"] =!= assoc["UUID"]
	]];
	Close[assoc["Socket"]]
);



WebSocketObject /: Normal[obj : WebSocketObject[asc: _Association?webSocketObjectQ]] := asc;


End[];
EndPackage[];
