BeginPackage["ToneAr`WebSocketLink`Private`"];

LF = "\n";
CR = "\r";
CRLF = "\r\n";

intToBitList::usage = "Convert an integer to a list of bits";
bitListToInt::usage = "Convert a list of bits to an integer";
webSocketObjectQ::usage = "Check if an object is a WebSocketObject";
webSocketFrameByteCount::usage = "Internal: return the byte count of the first complete WebSocket frame";

StartTLSServerProxy::usage = "Internal: start TLS server proxy, return {sslSocket, loopbackPort}";
StartTLSClientProxy::usage = "Internal: start TLS client proxy, return loopbackPort";

EndPackage[];
