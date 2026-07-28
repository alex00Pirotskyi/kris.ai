# Local authenticated IPC v1

Windows prefers named pipes; macOS and Linux prefer Unix-domain sockets. An authenticated loopback transport is the cross-platform compatibility path. Every transport uses the same versioned envelope, mutual authentication, peer identity, request ID, deadline, payload limit and replay protection.

Environment variables and command-line arguments cannot grant authority or carry reusable secrets. The authenticated channel transports an already-issued Capability Grant v2; it does not create or widen grants. The reference loopback test proves that an unrelated local process without the peer key cannot invoke a worker.
