# WebSocketLink

Wolfram Language tools for creating WebSocket clients and local WebSocket
servers, including text messages, binary `ByteArray` messages, JSON payloads,
ping/pong frames, close frames, and optional TLS for secure `wss://`
connections.

## Installation

Install the paclet from the Wolfram Resource Repository:
```wl
PacletInstall["ToneAr/WebSocketLink"];
Needs["ToneAr`WebSocketLink`"];
```

Or load the paclet from a local checkout:

```wl
PacletDirectoryLoad["/path/to/resource-paclet-WEBSOCKET-LINK"];
Needs["ToneAr`WebSocketLink`"];
```

For development from the repository root:

```wl
PacletDirectoryLoad[NotebookDirectory[]];
Needs["ToneAr`WebSocketLink`"];
```

## Basic Usage

Start a WebSocket server on an automatically selected local port:

```wl
receivedMessages = {};

server = WebSocketServerStart[
	"HandlerFunctions" -> <|
		"DataReceived" -> Function[event,
			AppendTo[receivedMessages, event["Data"]]
		]
	|>
];

server["Port"]
```

Connect a client and send a text message:

```wl
client = WebSocketConnect[
	"ws://localhost:" <> ToString[server["Port"]]
];

WriteString[client, "hello from client"];
Pause[0.1];
receivedMessages
```

Send a reply from the server-side connection object:

```wl
serverConnection = First[Values[server["ConnectedClients"]]];
serverConnection["SendMessage"]["hello from server"];

Read[client]
```

Send JSON as WebSocket text:

```wl
WriteString[
	client,
	ExportString[<|"event" -> "update", "count" -> 3|>, "RawJSON"]
];

Pause[0.1];
ImportString[Last[receivedMessages], "RawJSON"]
```

Send binary data:

```wl
BinaryWrite[client, ByteArray[{1, 2, 3, 4}]];
Pause[0.1];
Last[receivedMessages]
```

Close clients and servers when finished:

```wl
Close /@ {client, server};
```

## Secure WebSockets

`WebSocketServerStart` and `WebSocketConnect` support secure WebSocket
connections with `wss://` through the bundled Java TLS helper:

```wl
server = WebSocketServerStart[
	30000,
	"TLS" -> True,
	"Certificate" -> Automatic
];

client = WebSocketConnect[
	"wss://localhost:30000",
	"VerifyPeer" -> False
];
```

For production use, provide an explicit certificate and keep peer verification
enabled where possible.

## Frame Helpers

The paclet also exposes lower-level frame helpers:

```wl
WebSocketFrameImport[WebSocketFrameCreate["standalone frame"]]
Normal[WebSocketFrameCreate[Ping]]
```

## Public Symbols

- `WebSocketServerStart`
- `WebSocketConnect`
- `WebSocketObject`
- `WebSocketFrameCreate`
- `WebSocketFrameImport`
- `$WebSocketServers`
- `$WebSocketClients`
- `Ping`
- `Pong`

## Tests

Run the test suite from the repository root:

```wl
TestReport["Resources/Tests/WebSocketLink.wlt"]
```

The integration tests open loopback TCP sockets and choose an available local
port automatically.

## Java TLS Helper

The prebuilt TLS helper jar is committed at `Java/WebSocketTLS.jar`. Rebuild it
only when `WebSocketTLS/WebSocketTLS.java` changes.

Use the Wolfram Language bundled JDK:

```bash
WL_JAVAC="/path/to/Wolfram/SystemFiles/Java/Linux-x86-64/bin/javac"
WL_JAR="/path/to/Wolfram/SystemFiles/Java/Linux-x86-64/bin/jar"

cd WebSocketTLS
mkdir -p classes
$WL_JAVAC -d classes WebSocketTLS.java
$WL_JAR cf ../Java/WebSocketTLS.jar -C classes .
```

See `WebSocketTLS/README.md` for platform-specific paths and verification
steps.

## Notes

- Servers remain active until their `WebSocketObject` is closed.
- The paclet uses local and network sockets; release builds should disclose
  local system/network interaction.
- JSON payloads are sent as text frames using `ExportString[..., "RawJSON"]`.
- Binary payloads are sent and received as `ByteArray` values.
