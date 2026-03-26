# Custom Adapters

## Description

LiveStash uses an adapter-based architecture to manage the storage and retrieval of LiveView state. While it comes with built-in adapters for Browser Memory and ETS, the system is designed to be fully extensible.

By implementing the `LiveStash.Adapter` behaviour, the community can create and plug in custom adapters to store state in alternative persistence options.

For more check the `LiveStash.Adapter` behaviour.

### Optional callbacks

If your custom adapter relies on background processes (similar to how the ETS adapter runs a cleanup task), you can implement the standard child specification:

- **`child_spec(args)`**: An optional callback. When implemented, LiveStash can automatically start and supervise your adapter's processes under its own supervision tree.

## Configuration

Configuration options for specific adapters should be defined under the `:live_stash` application in your project's `config.exs` file.

```elixir
config :live_stash, adapters: [LiveStash.Adapters.ETS], ets_cleanup_interval: 60_000
```
