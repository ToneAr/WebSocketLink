# WebSocketTLS Java Helper

`WebSocketTLS.java` is a small Java helper class that provides TLS socket management for the WebSocketLink paclet via JLink. It handles SSL context creation, self-signed certificate generation, and bidirectional pipe threads between SSL sockets and plain loopback sockets.

## Building

Use WL's bundled JDK so the compiled bytecode targets the same JVM that JLink uses at runtime.

```bash
WL_JAVAC="/path/to/Wolfram/15.0/SystemFiles/Java/Linux-x86-64/bin/javac"
WL_JAR="/path/to/Wolfram/15.0/SystemFiles/Java/Linux-x86-64/bin/jar"
```

Adjust the path for your platform and WL version:
- **Linux**: `SystemFiles/Java/Linux-x86-64/bin/`
- **macOS**: `SystemFiles/Java/MacOSX-x86-64/bin/` (Intel) or `SystemFiles/Java/MacOSX-ARM64/bin/` (Apple Silicon)
- **Windows**: `SystemFiles\Java\Windows-x86-64\bin\`

```bash
cd WebsocketTLS
mkdir -p classes
$WL_JAVAC -d classes WebSocketTLS.java
$WL_JAR cf ../Java/WebSocketTLS.jar -C classes .
```

Verify the JAR contents:

```bash
$WL_JAR tf ../Java/WebSocketTLS.jar
# Expected:
# META-INF/
# META-INF/MANIFEST.MF
# websocketlink/
# websocketlink/WebSocketTLS$TrustAllCerts.class
# websocketlink/WebSocketTLS.class
```

## Notes

- The pre-compiled `WebSocketTLS.jar` is committed to the repo. Rebuild only when `WebSocketTLS.java` changes.
- The `classes/` directory is intermediate build output and is not committed.
- Do not use a system `javac` — it may target a different JVM version than WL's embedded JRE, causing `UnsupportedClassVersionError` at runtime.
