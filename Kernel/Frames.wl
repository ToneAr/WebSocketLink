BeginPackage["WSLink`", {
	"WSLink`PackageScope`"
}];

Begin["`Private`"];

(* -----------------------WSFrameCreate------------------------------
 * Description:  Create a frame ByteArray
 * Return:       _ByteArray
 *)
WSFrameCreate // ClearAll
WSFrameCreate // Options = {
	"Masking" -> True
};
WSFrameCreate[ data: (_String | _ByteArray), OptionsPattern[] ] := Module[{
		payloadLength,bitList,
		opcode = intToBitList[
			Switch[Head[data],
				String, 1,(* 0x1 *)
				ByteArray, 2, (* 0x2 *)
				_, $Failed
			],
			4
		],
		mask = If[OptionValue["Masking"], 1, 0],
		maskingKey = If[OptionValue["Masking"],
			intToBitList[RandomInteger[2^32 - 1], 32],
			{}
		]
	},
	
	bitList = ResourceFunction["ByteArrayToBitList"][
		If[MatchQ[data, _String],
			ByteArray[ ToCharacterCode[data, "UTF-8"] ],
			data
		]
	];

	
	If[OptionValue["Masking"],
		bitList = Flatten @ Map[Function[block,
				BitXor[ block, Take[maskingKey, Length @ block] ]
			],
			Partition[bitList, UpTo[32]](* Partition into 32 bit blocks *)
		]
	];
	
	payloadLength = With[{ byteCount =  (Length @ bitList)/8 },
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
		
	(* Make payload ByteArray as per RFC-6455 *)
	 
	ResourceFunction["BitListToByteArray"] @ Flatten @ {
		(*FIN - No benefit from multipart in this implementation *)
		1 ,
		(* RSV1-3 - Inert and used for extensions *)
		0, 0, 0,
		opcode,
		mask,
		payloadLength,
		maskingKey,
		(* Payload *)
		bitList
	}
];

(* -----------------------WSFrameImport------------------------------
 * Description:  Import a frame ByteArray
 * Return:       _String | _ByteArray
 *)
WSFrameImport // ClearAll
WSFrameImport // Options = {
	"Masking" -> True
};
WSFrameImport[ frame_ByteArray, OptionsPattern[] ]:= Module[{
		fin, rsv, opcode, isMasked,payloadByteCount, mask,offset,payload,
		bitList = ResourceFunction["ByteArrayToBitList"] @ frame
	},
	fin = Replace[bitList[[1]],{ 1 -> True, 0 -> False}];
	opcode = FromDigits[bitList[[5;;8]], 2];
	isMasked = Replace[bitList[[9]],{ 1 -> True, 0 -> False}];
	With[{ initialLength = FromDigits[bitList[[10;;16]], 2]},
		payloadByteCount = Which[
			initialLength < 126,
				offset = 0;
				initialLength,
			initialLength == 126,
				offset = 16;
				bitListToInt @ bitList[[17;;32]],
			initialLength == 127,
				offset = 64;
				bitListToInt @ bitList[[17;;80]]
		]
	];
	If[isMasked,
		mask= bitList[[ (17+offset) ;; (17+offset+ 31) ]];
		offset = (17+offset+ 31)
	];
	payload = ResourceFunction["BitListToByteArray"] @ If[isMasked,
		 Flatten @ Map[Function[block,
				BitXor[ block, Take[mask, Length @ block] ]
			],
			Partition[bitList[[(offset+1);;]], UpTo[32]]
		],
		bitList[[(offset+1);;]]
	];
	Switch[opcode,
		1 /; fin,
			ByteArrayToString[payload, "UTF-8"],
		2,
			payload
	]
];

End[];
EndPackage[];
