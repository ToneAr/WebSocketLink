(
	Get[#]
)& /@ {
	"TonyAristeidou`WebSocketLink`PublicScope`",
	"TonyAristeidou`WebSocketLink`PackageScope`",

	"TonyAristeidou`WebSocketLink`Source`Common`",
	"TonyAristeidou`WebSocketLink`Source`Frames`",
	"TonyAristeidou`WebSocketLink`Source`Server`",
	"TonyAristeidou`WebSocketLink`Source`Objects`"
};

$ContextPath = DeleteCases[$ContextPath, "TonyAristeidou`WebSocketLink`PackageScope`"];