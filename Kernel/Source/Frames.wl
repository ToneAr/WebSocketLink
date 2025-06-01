BeginPackage["ToneAr`WebSocketLink`", {
	"ToneAr`WebSocketLink`Private`"
}];

Begin["`FileScope`Frames`Private`"];

(* -----------------------WebSocketFrameCreate------------------------------
 * Description:  Create a frame ByteArray
 * Return:       _ByteArray
 *)
WebSocketFrameCreate // ClearAll
WebSocketFrameCreate // Options = {
	Masking -> False,
	"Opcode" -> Automatic
};
WebSocketFrameCreate[Close, opts: OptionsPattern[]] := WebSocketFrameCreate[
	"",
	"Opcode" -> 8,
	opts
];
WebSocketFrameCreate[Ping, opts: OptionsPattern[]] := WebSocketFrameCreate[
	"",
	"Opcode" -> 9,
	opts
];
WebSocketFrameCreate[Pong, opts: OptionsPattern[]] := WebSocketFrameCreate[
	"",
	"Opcode" -> 10,
	opts
];
WebSocketFrameCreate[ data: (_String | _ByteArray), OptionsPattern[] ] := Module[{
		payloadLength, payloadBitList,
		opcode = intToBitList[
			Replace[Automatic :>
				Switch[Head[data],
					String, 1,(* 0x1 *)
					ByteArray, 2, (* 0x2 *)
					_, $Failed
				]
			] @ OptionValue["Opcode"],
			4
		],
		mask = If[OptionValue[Masking], 1, 0],
		maskingKey = If[OptionValue[Masking],
			intToBitList[RandomInteger[2^32 - 1], 32],
			{}
		]
	},

	payloadBitList = ResourceFunction["ByteArrayToBitList"][
		If[MatchQ[data, _String],
			ByteArray[ ToCharacterCode[data, "UTF-8"] ],
			data
		]
	];


	If[OptionValue[Masking],
		payloadBitList = Flatten @ Map[Function[block,
				BitXor[ block, Take[maskingKey, Length @ block] ]
			],
			(* Partition payload into 32 bit blocks *)
			Partition[payloadBitList, UpTo[32]]
		]
	];

	(* Determine payload length according to RFC-6455.
	 * This follows the WebSocket framing where if payload byte length is:
	 * - 0-125: The payload length field is the value of the length
	 * - 126: The following 2 bytes interpret as a 16-bit unsigned integer for payload length
	 * - 127: The following 8 bytes interpret as a 64-bit unsigned integer for payload length
	 *)
	payloadLength = With[{ byteCount = Length[payloadBitList]/8 },
		Which[
			byteCount < 126,
				intToBitList[ byteCount, 7 ],
			126 <= byteCount <= 65535,
				{
					intToBitList[ 126 ],
					intToBitList[ byteCount, 16]
				},
			True,
				{
					intToBitList[ 127 ],
					intToBitList[ byteCount, 64]
				}
		]
	];

	ResourceFunction["BitListToByteArray"] @ Flatten @ {
		1,       (* FIN - No benefit from multipart in this implementation *)
		0, 0, 0, (* RSV1-3 - Inert and used for extensions *)
		opcode,
		mask,
		payloadLength,
		maskingKey,
		payloadBitList
	}
];


(* -----------------------WebSocketFrameImport------------------------------
 * Description:  Import a frame ByteArray
 * Return:       _String | _ByteArray
 *)
WebSocketFrameImport // ClearAll
WebSocketFrameImport // Options = {
	"Masking" -> True
};
WebSocketFrameImport[ frame_ByteArray, OptionsPattern[] ] :=
	Module[{
			fin, opcode, isMasked,payloadByteCount, mask, payload,
			lengthOffset = 0,
			maskOffset = 0,
			payloadOffset = 17,
			bitList = ResourceFunction["ByteArrayToBitList"] @ frame
		},
		fin = Replace[bitList[[1]],{ 1 -> True, 0 -> False}];
		opcode = bitListToInt @ bitList[[5;;8]];
		isMasked = Replace[bitList[[9]],{1 -> True, 0 -> False}];
		(* Determine payload length according to RFC-6455.
		* This follows the WebSocket framing where if payload byte length is:
		* - 0-125: The payload length field is the value of the length
		* - 126: The following 2 bytes interpret as a 16-bit unsigned integer for payload length
		* - 127: The following 8 bytes interpret as a 64-bit unsigned integer for payload length
		*)
		payloadByteCount = With[{
				initialLength = bitListToInt @ bitList[[10;;16]]
			},
			Which[
				initialLength < 126,
					initialLength,
				initialLength == 126,
					lengthOffset = 16;
					bitListToInt @ bitList[[17 ;; 32]],
				initialLength == 127,
					lengthOffset = 64;
					bitListToInt @ bitList[[17 ;; 80]]
			]
		];
		If[isMasked,
			mask = bitList[[
				Span[
					payloadOffset + lengthOffset,
					payloadOffset + lengthOffset + 31
				]
			]];
			maskOffset = 32
		];
		payloadOffset += (lengthOffset + maskOffset);
		payload =
			ResourceFunction["BitListToByteArray"] @
			If[isMasked,
				(* Apply mask if necessary *)
				Flatten @ Map[Function[block,
						BitXor[ block, Take[mask, Length @ block] ]
					],
					Partition[bitList[[payloadOffset;;]], UpTo[32]]
				],
				(* Else just take the payload *)
				bitList[[ payloadOffset ;; All ]]
			];
		Switch[opcode,
			0,
				(* Continuation frame *)
				payload,
			1 /; fin,
				(* Text frame *)
				ByteArrayToString[payload, "UTF-8"],
			2,
				(* Binary frame *)
				payload,
			8,
				(* Close frame *)
				Null,
			9,
				(* Ping frame *)
				"Ping",
			10,
				(* Pong frame *)
				"Pong",
			_,
				(* Unknown frame *)
				$Failed
		]
	];


End[];
EndPackage[];
