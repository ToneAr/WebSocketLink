(
	Get[#]
)& /@ {
	"WebSocketLink`PublicScope`",
	"WebSocketLink`PackageScope`",

	"WebSocketLink`Source`Common`",
	"WebSocketLink`Source`Frames`",
	"WebSocketLink`Source`Server`",
	"WebSocketLink`Source`Objects`"
};

$ContextPath = DeleteCases[$ContextPath, "WebSocketLink`PackageScope`"];