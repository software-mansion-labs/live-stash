# ETS

## Description

In this mode, the stashed state is securely stored in an ETS table on the Elixir node. Instead of sending the entire payload to the browser, the client only receives and stores a lightweight, cryptographically signed reference (a stash ID and a node hint). Upon reconnection, LiveStash uses this reference to retrieve the state from the server's memory.

## When to use

Choose the ETS mode when:

- **Payloads are large:** You need to stash substantial amounts of data that would otherwise degrade WebSocket performance or exceed browser storage limits.
- **Memory footprint matters:** Storing large payloads server-side increases your server's memory usage, so configure TTL (Time-To-Live) responsibly based on data size and relevance to avoid memory leaks or bloat.
- **Highly sensitive data:** You want to ensure the actual state never leaves your infrastructure and is not exposed to the browser.

> #### Warning {: .warning}
>
> While the data itself remains on the server, the client-side reference ID is vulnerable to Cross-Site Scripting (XSS). Without configuring a session-bound secret, an attacker can steal this reference and use your application as a black box to interact with the stashed data.

### State recovery

Stashed state is recovered from the ETS table.

In a clustered environment, if the client reconnects to a different server node, LiveStash uses RPC to fetch the state from the previous node.

> #### Note {: .info}
>
> For cross-node recovery to work, your application must form a connected BEAM cluster (e.g., by using [libcluster](https://hexdocs.pm/libcluster)). In this scenario, the state is deleted from the old node and securely saved in the new one. To optimize finding the correct node, the **node hint** saved in the browser is utilized.

### Reseting the stash

Stashed state is automatically cleared after the TTL passes, provided the process owning the state is dead. If the process is still alive, the `delete_at` time gets bumped by the TTL.

State can also be cleared manually by calling `LiveStash.reset_stash/1`.

## Configuration

### Expiration (TTL)

Stashed data in server mode has a Time-To-Live (TTL) to prevent stale state from persisting indefinitely. The default TTL is 5 minutes. You can adjust this using the `:ttl` option.

```elixir
use LiveStash, adapter: LiveStash.Adapters.ETS, ttl: 60 * 1000,
```

### Cleanup interval

Determines how often the background task runs to remove expired state records from the ETS table.

**Default:** `60_000` ms (1 minute)

To override this, add the following to your `config/config.exs`:

```elixir
config :live_stash, adapters: [LiveStash.Adapters.ETS], ets_cleanup_interval: 60_000
```

### ETS table name

Defines the name of the ETS table created by LiveStash to hold the server state. You might want to change this if you need to avoid naming collisions with other libraries in your application.

Default: `:live_stash_server_storage`

To override this, add the following to your `config/config.exs`:

```elixir
config :live_stash, adapters: [LiveStash.Adapters.ETS], ets_table_name: :my_custom_table_name
```

### Cleanup batch size

Specifies how many expired records the cleanup task will delete in a single batch. Limiting the batch size prevents the cleanup process from blocking the ETS table or the Erlang scheduler for too long during heavy loads.

Default: `100`

To override this, add the following to your `config/config.exs`:

```elixir
config :live_stash, adapters: [LiveStash.Adapters.ETS], ets_cleanup_batch_size: 100
```

## Security

By default, LiveStash uses a hardcoded default secret (`"live_stash"`) to secure your data. For production environments, it is highly recommended to tie the stash to a specific user session to prevent tampering or data leakage.

You can do this by providing a `:session_key`. LiveStash will extract the value from the connection session securely hash it (SHA-256) to use as the operational secret. If you provide the key and it is not present in the session, `Argument Error` will be raised.

In ETS mode, this operational secret is used as part of the record ID for your stashed state.

```elixir
use LiveStash, adapter: LiveStash.Adapters.ETS, session_token: "user_token"
```
