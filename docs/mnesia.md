# Mnesia

## Description

The Mnesia adapter stores LiveView state on the server using Mnesia through
the [memento](https://github.com/sheharyarn/memento) wrapper. Add it to your dependencies to use this adapter. The table is stored in memory. It uses Mnesia replication to make state recovery easier, and rolling redeploys possible. State is stashed into native Mnesia table copies, recovered from the local copy on reconnect, and cleared
when you reset the stash.

## Replication

The adapter always configures native Mnesia table copies on connected nodes and
relies on Mnesia replication for writes/deletes.

Recovery is local because every serving node is expected to have the table
copy already.

## When to use

Choose the Mnesia adapter when:

- **BEAM native solution:** You want a fully server-side solution that leverages the BEAM's distributed capabilities without relying on external services like Redis.
- **State durability (Rolling Redeploys):** You need stashed state to survive rolling server restarts and redeployments. Thanks to Mnesia's replication, the state persists as long as at least one node in the cluster remains active. _(Note: A simultaneous shutdown of the entire cluster will clear the state)._
- **Clustering:** You have a clustered application where client can connect to different nodes.

### Reseting the stash

Stashed state is automatically cleared after the TTL passes, provided the process owning the state is dead. If the process is still alive, the `delete_at` time gets bumped by the TTL.

State can also be cleared manually by calling `LiveStash.reset_stash/1`.

## Configuration

### Activating the adapter

Remember to define adapters you would like to activate in your `config.exs` file.

```elixir
config :live_stash, adapters: [LiveStash.Adapters.Mnesia]
```

### Expiration (TTL)

Stashed data in server mode has a Time-To-Live (TTL) to prevent stale state from persisting indefinitely. You can adjust this using the `:ttl` option.

**Default:** `300` seconds (5 minutes)

```elixir
use LiveStash, adapter: LiveStash.Adapters.Mnesia, ttl: 60, stored_keys: [:count]
```

### Cleanup interval

Determines how often the background task runs to remove expired state records from the Mnesia table.

**Default:** `60_000` ms (1 minute)

To override this, add the following to your `config/config.exs`:

```elixir
config :live_stash, adapters: [LiveStash.Adapters.Mnesia], mnesia_cleanup_interval: 60_000
```

### Split brain resolution strategy

By default, in reaction to `:inconsistent_database` event from Mnesia, LiveStash deletes the state on the node larger lexicographically (`nodeA > nodeB`). You can pass `auto_heal_mnesia: false` and implement your own strategy.

```elixir
config :live_stash, adapters: [LiveStash.Adapters.Mnesia], auto_heal_mnesia: false
```

## Security

By default, LiveStash uses a hardcoded default secret (`"live_stash"`) to secure your data. For production environments, it is highly recommended to tie the stash to a specific user session to prevent tampering or data leakage.

You can do this by providing a `:session_key`. LiveStash will extract the value from the connection session securely hash it (SHA-256) to use as the operational secret. If you provide the key and it is not present in the session, `Argument Error` will be raised.

In Mnesia mode, this operational secret is used as part of the record ID for your stashed state.

```elixir
use LiveStash, adapter: LiveStash.Adapters.Mnesia, session_key: "user_token", stored_keys: [:count]
```
