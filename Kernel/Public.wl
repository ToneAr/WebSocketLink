BeginPackage["ToneAr`WebSocketLink`"];

WebSocketObject::usage = "Represents a WebSocket connection";

$WebSocketClients::usage = "List of active WebSocket client objects";
$WebSocketServers::usage = "List of active WebSocket server objects";

WebSocketConnect::usage = "Connect to a WebSocket server";

WebSocketServerStart::usage = "Start the server";
WebSocketServerStop::usage = "Stop the server";
WebSocketRunningQ::usage = "Check if the server is running";

WebSocketFrameCreate::usage = "Create a frame ByteArray";
WebSocketFrameImport::usage = "Import a frame ByteArray";

Ping::usage = "Inert symbol used to create a Ping frame";
Pong::usage = "Inert symbol used to create a Pong frame";

EndPackage[];
