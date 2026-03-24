# Custom Adapters

## Description

LiveStash uses an adapter-based architecture to manage the storage and retrieval of LiveView state. While it comes with built-in adapters for Browser Memory and ETS, the system is designed to be fully extensible.

By implementing the `LiveStash.Adapter` behaviour, the community can create and plug in custom adapters to store state in alternative persistence options, such as Redis.

## The Behaviour

Any custom adapter must implement the `LiveStash.Adapter` behaviour. This ensures a unified interface for LiveStash to interact with your chosen storage mechanism.

Here are the standard callbacks your module needs to implement:

- **`init_stash(socket, session, opts)`**: Initializes the stash state for the given LiveView socket. It receives the connection session and any options passed during configuration. Returns the updated socket.
- **`stash_assigns(socket, keys)`**: Handles the actual persistence of the specified assigns keys. Returns the updated socket.
- **`recover_state(socket)`**: Retrieves the stored state and attempts to restore it to the socket. It must return a tuple containing the recovery status (`:recovered`, `:not_found`, `:new`, or `:error`) and the updated socket.
- **`reset_stash(socket)`**: Clears the currently stored state for the socket. Returns the updated socket.

### Optional callbacks

If your custom adapter relies on background processes (similar to how the ETS adapter runs a cleanup task), you can implement the standard child specification:

- **`child_spec(args)`**: An optional callback. When implemented, LiveStash can automatically start and supervise your adapter's processes under its own supervision tree.

## Configuration

Configuration options for specific adapters should be defined under the `:live_stash` application in your project's `config.exs` file.

```elixir
config :live_stash, adapters: [LiveStash.Adapters.ETS], ets_cleanup_interval: 60_000
```
