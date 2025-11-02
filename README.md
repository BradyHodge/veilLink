# VeilLink

A lightweight, high-performance multi-threaded TCP packet proxy written in Erlang with WebSocket support.

## Overview

VeilLink is a simple yet powerful packet forwarding proxy that leverages Erlang's concurrency model to handle multiple simultaneous connections efficiently. Each proxy rule runs in its own process, and each client connection spawns dedicated forwarding processes for bidirectional data transfer.

## Features

- **Multi-threaded Architecture**: Each listening port and connection runs in separate Erlang processes
- **Bidirectional Forwarding**: Full-duplex data transfer between client and destination
- **CSV Configuration**: Simple, human-readable configuration file
- **WebSocket Compatible**: Raw packet forwarding supports WebSocket and other TCP protocols
- **Concurrent Connections**: Handle multiple clients per port simultaneously
- **Low Latency**: Direct packet forwarding with minimal overhead

## Requirements

- Erlang/OTP (any recent version)

## Installation

1. Clone the repository:
```bash
git clone https://github.com/bradyhodge/veilLink.git
cd veillink
```

2. Compile the module:
```bash
erlc main.erl
```

## Configuration

Create a `config.csv` file in the same directory as the executable with the following format:

```csv
<listen_port>,<forward_ip>,<forward_port>
```

### Example config.csv

```csv
8080,192.168.1.100,80
8443,example.com,443
9000,127.0.0.1,3000
```

This configuration will:
- Forward traffic from local port 8080 to 192.168.1.100:80
- Forward traffic from local port 8443 to example.com:443
- Forward traffic from local port 9000 to 127.0.0.1:3000

## Usage

### Start the proxy:

```bash
erl -noshell -s main start
```

Or from the Erlang shell:

```erlang
c(main).
main:start().
```

### Stop the proxy:

Press `Ctrl+C` twice or use:

```erlang
init:stop().
```

## How It Works

1. **Configuration Loading**: Reads `config.csv` and parses proxy rules
2. **Listener Processes**: Spawns a listener process for each configured port
3. **Connection Handling**: When a client connects, spawns a new process to handle that connection
4. **Bidirectional Forwarding**: Creates two processes per connection:
   - One for client → server traffic
   - One for server → client traffic
5. **Automatic Cleanup**: Closes sockets when either end disconnects

## Architecture

```
[Client] ←→ [VeilLink:8080] ←→ [Target Server:80]
              ↓
         [Listener Process]
              ↓
         [Connection Handler]
              ↓
     [Forward Loop] ↔ [Forward Loop]
     (client→server)   (server→client)
```

## Use Cases

- **Reverse Proxy**: Route traffic to backend services
- **WebSocket Proxy**: Forward WebSocket connections transparently
- **Port Forwarding**: Expose services on different ports
- **Development**: Test applications behind a proxy
- **Load Distribution**: Combine with DNS or external load balancers

## Performance

VeilLink is built on Erlang's lightweight process model:
- Minimal memory footprint per connection
- Efficient message passing between processes
- Handles thousands of concurrent connections
- Non-blocking I/O operations

## Error Handling

- Invalid configuration entries are skipped
- Connection failures are logged to stdout
- Socket errors trigger automatic cleanup
- Failed listeners are reported but don't stop other ports

## Limitations

- No SSL/TLS termination (transparent proxy only)
- No load balancing between multiple backends
- No connection pooling or rate limiting
- Configuration requires restart to update

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.