# VeilLink
A lightweight, high-performance multi-threaded TCP/UDP packet proxy written in Erlang with WebSocket support.

## Overview
VeilLink is a simple yet powerful packet forwarding proxy that leverages Erlang's concurrency model to handle multiple simultaneous connections efficiently. Each proxy rule runs in its own process, and each client connection spawns dedicated forwarding processes for bidirectional data transfer.

## Features
- **Multi-threaded Architecture**: Each listening port and connection runs in separate Erlang processes
- **TCP & UDP Support**: Forward both TCP and UDP traffic with protocol-specific handling
- **Bidirectional Forwarding**: Full-duplex data transfer between client and destination
- **CSV Configuration**: Simple, human-readable configuration file
- **WebSocket Compatible**: Raw packet forwarding supports WebSocket and other TCP protocols
- **Game Server Support**: UDP forwarding works with game protocols (e.g., Minecraft Bedrock, voice chat)
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
<protocol>,<listen_port>,<forward_ip>,<forward_port>
```

The protocol field accepts `tcp` or `udp` (case-insensitive).

### Example config.csv
```csv
tcp,8080,192.168.1.100,80
tcp,8443,example.com,443
udp,19132,10.0.0.5,19132
udp,5353,8.8.8.8,53
```

This configuration will:
- Forward TCP traffic from local port 8080 to 192.168.1.100:80
- Forward TCP traffic from local port 8443 to example.com:443
- Forward UDP traffic from local port 19132 to 10.0.0.5:19132 
- Forward UDP traffic from local port 5353 to 8.8.8.8:53

### Legacy Format
The legacy 3-column format is still supported and defaults to TCP:
```csv
8080,192.168.1.100,80
```

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

### TCP Forwarding
1. **Configuration Loading**: Reads `config.csv` and parses proxy rules
2. **Listener Processes**: Spawns a listener process for each configured port
3. **Connection Handling**: When a client connects, spawns a new process to handle that connection
4. **Bidirectional Forwarding**: Creates two processes per connection:
   - One for client → server traffic
   - One for server → client traffic
5. **Automatic Cleanup**: Closes sockets when either end disconnects

### UDP Forwarding
1. **Listener Process**: Opens a UDP socket and listens for datagrams
2. **Client Tracking**: Uses ETS tables to track client addresses and their associated forward handlers
3. **Per-Client Handlers**: Each unique client (IP:port) gets a dedicated handler process with its own forward socket
4. **Response Routing**: Responses from the destination are automatically routed back to the correct client
5. **Idle Timeout**: UDP handlers automatically clean up after 5 minutes of inactivity

## Use Cases
- **Reverse Proxy**: Route traffic to backend services
- **WebSocket Proxy**: Forward WebSocket connections transparently
- **Game Server Proxy**: Forward Minecraft Bedrock, voice chat, and other UDP-based game traffic
- **DNS Forwarding**: Redirect DNS queries to custom resolvers
- **Port Forwarding**: Expose services on different ports
- **Development**: Test applications behind a proxy
- **Load Distribution**: Combine with DNS or external load balancers

## Performance
VeilLink is built on Erlang's lightweight process model:
- Minimal memory footprint per connection
- Efficient message passing between processes
- Handles thousands of concurrent connections
- Non-blocking I/O operations
- UDP handlers automatically expire after idle timeout

## Error Handling
- Invalid configuration entries are skipped
- Connection failures are logged to stdout
- Socket errors trigger automatic cleanup
- Failed listeners are reported but don't stop other ports
- UDP client mappings are cleaned up on handler exit

## Limitations
- No SSL/TLS termination (transparent proxy only)
- No load balancing between multiple backends
- No connection pooling or rate limiting
- Configuration requires restart to update
- UDP idle timeout is fixed at 5 minutes

## Contributing
Contributions are welcome! Please feel free to submit issues or pull requests.
