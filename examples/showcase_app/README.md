# ShowcaseApp

This projects features a few examples where you can see LiveStash in action:

## Content description

### Counter

- Counter Default - no state recovery
- Counter Client - client mode LiveStash state recovery
- Counter Server - server mode LiveStash state recovery

### Tic Tac Toe

- Tic Tac Toe Default - no state recovery
- Tic Tac Toe Client - client mode LiveStash state recovery
- Tic Tac Toe Server - server mode LiveStash state recovery
- Auth Tic Tac Toe Client - client mode LiveStash state recovery with authentication
- Auth Tic Tac Toe Server - server mode LiveStash state recovery with authentication

## Getting started

To start your Phoenix server:

- Run `mix setup` to install and setup dependencies
- Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Select an example and play around with it to save some state. Now press the Disconnect Socket button in the bottom-right corner, then press Connect Socket and watch the state being recovered (or not if you selected Default example)

### Cluster example - Docker

In a cluster environment the client may connect to a different server after the reconnect. Because of that, in server mode LiveStash sometimes retrieves the state from other nodes. To test this, run this code if you have Docker set up on your machine:

```bash
docker compose up --build
```

This should start two ShowcaseApp nodes and Nginx as a load balancer with round-robin strategy on port 8080.
