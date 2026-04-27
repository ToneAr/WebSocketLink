With[{
		contextPath =
			Map[
				StringJoin["Source`", #, "`"]& @* StringDelete[".wl"] @* FileNameTake,
				FileNames[
					"*.wl",
					FileNameJoin[{
						PacletObject["ToneAr/WebSocketLink"]["Location"],
						"Kernel", "Source"
					}]
				]
			]
	},
	(
		Get["ToneAr`WebSocketLink`"<>#]
	)& /@ {
		"Public`",
		"Private`",
		Splice[contextPath]
	}
];

