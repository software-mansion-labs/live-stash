# Redis

## Description

In this mode, the stashed state is securely stored in Redis on the server. Instead of sending the full payload to the browser, the client only receives and stores a lightweight stash ID. Upon reconnection, LiveStash uses that reference to retrieve the state from Redis.

The assigns you want to persist are declared once at the module level with `stored_keys: [...]`, and `stash/1` only rewrites the Redis entry when those values change.

## When to use

Choose the Redis mode when:

- **Payloads are large:** You need to stash substantial amounts of data that would otherwise degrade WebSocket performance, exceed browser storage limits or consume excessive memory on your server.
- **Fitting architecture:** You already use Redis in your stack and want to leverage it for state persistence.
- **Highly sensitive data:** You want to ensure the actual state never leaves your infrastructure and is not exposed to the browser.

> #### Warning {: .warning}
>
> While the data itself remains on the server, the client-side stash ID is still vulnerable to Cross-Site Scripting (XSS). Without configuring a session-bound secret, an attacker can steal this reference and use your application as a black box to interact with the stashed data.

### State recovery

Stashed state is recovered from Redis.

Because the data lives in Redis, any node that can reach the same Redis deployment can recover it without cross-node RPC.

### Resetting the stash

Stashed state is automatically cleared after the TTL passes, provided the process owning the state is dead. If the process is still alive, the `delete_at` time gets bumped by the TTL.

State can also be cleared manually by calling `LiveStash.reset_stash/1`.

## Configuration

### Redis connection

Defines how LiveStash connects to Redis. The value is read from `config :live_stash, :redis` and can be:

- a Redis URI string
- a `{uri, extra_opts}` tuple
- a keyword list of Redix options

This is consistent with the [Redix API](https://github.com/whatyouhide/redix), the library that LiveStash uses under the hood to interact with Redis.

Example:

```elixir
config :live_stash,
  adapters: [LiveStash.Adapters.Redis],
  redis: "redis://localhost:6379"
```

## Security

By default, LiveStash uses a hardcoded default secret (`"live_stash"`) to secure your data. For production environments, it is highly recommended to tie the stash to a specific user session to prevent tampering or data leakage.

You can do this by providing a `:session_key`. LiveStash will extract the value from the connection session, securely hash it (SHA-256), and use it as the operational secret. If you provide the key and it is not present in the session, `ArgumentError` will be raised.

In Redis mode, this operational secret is used as part of the Redis key for your stashed state.

```elixir
use LiveStash, adapter: LiveStash.Adapters.Redis, session_key: "user_token", stored_keys: [:count]
```
