BeginPackage["WebSocketLink`"];

WebSocketObject::usage = "Represents a WebSocket connection";

$WebSocketClients::usage = "List of active WebSocket client objects";
$WebSocketServers::usage = "List of active WebSocket server objects";

WebSocketServerStart::usage = "Start the server";
WebSocketServerStop::usage = "Stop the server";
IsWebSocketServerRunning::usage = "Check if the server is running";

WebSocketFrameCreate::usage = "Create a frame ByteArray";
WebSocketFrameImport::usage = "Import a frame ByteArray";

EndPackage[];
