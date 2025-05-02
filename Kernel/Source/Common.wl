BeginPackage["TonyAristeidou`WebSocketLink`Common`", {
	"TonyAristeidou`WebSocketLink`",
	"TonyAristeidou`WebSocketLink`PackageScope`"
}];
Begin["`Private`"];

intToBitList[ int_Integer, block_Integer : Nothing ] :=
	IntegerDigits @@ { int, 2, block }
bitListToInt[ bitList_List ] :=
	FromDigits[ bitList, 2 ]


$WebSocketClients = Replace[$WebSocketClients, Except[_Association] -> <| |>];
$WebSocketServers = Replace[$WebSocketServers, Except[_List] -> { }];

End[];
EndPackage[];
