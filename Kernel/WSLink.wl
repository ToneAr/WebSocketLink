(
	Get[#]
)& /@ {
	"WSLink`PublicScope`",
	"WSLink`PackageScope`",
	"WSLink`Common`",
	"WSLink`Frames`",
	"WSLink`Server`"
};

$ContextPath = DeleteCases[$ContextPath, "WSLink`PackageScope`"];