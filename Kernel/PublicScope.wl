BeginPackage["WSLink`"];

$WebSocketClients::usage = "List of active WebSocket client objects";

WSServerStart::usage = "Start the server";
WSServerStop::usage = "Stop the server";
IsWSServerRunning::usage = "Check if the server is running";

WSFrameCreate::usage = "Create a frame ByteArray";
WSFrameImport::usage = "Import a frame ByteArray";

testFunction;

EndPackage[];
