# Configuration

LiveStash is configured on a per live view basis by passing options directly to the `use LiveStash` macro.

```elixir
use LiveStash, mode: :client, security_mode: :encrypt, session_key: "user_token"
```

## Storage mode

You can control where the stashed data is kept using the `:mode` option. LiveStash supports two modes:

- [Server](./modes.md) (default) - The data is kept on the server side.
- [Client](./modes.md) - The data is saved in the client browser.

```elixir
use LiveStash, mode: :client
```

## Security

By default, LiveStash uses a hardcoded default secret (`"live_stash"`) to secure your data. For production environments, it is highly recommended to tie the stash to a specific user session to prevent tampering or data leakage.

You can do this by providing a `:session_key`. LiveStash will extract the value from the connection session securely hash it (SHA-256) to use as the operational secret. If you provide the key and it is not present in the session, `Argument Error` will be raised.

```elixir
use LiveStash, session_key: "user_token"
```

## Client mode

### Security

Additionally, you can configure how the data is secured in client mode using the `:security_mode` option. It defaults to `:sign`, but can be set to `:encrypt` for sensitive payloads.

```elixir
use LiveStash, mode: :client, security_mode: :encrypt
```

## Server mode

### Expiration (TTL)

Stashed data in server mode has a Time-To-Live (TTL) to prevent stale state from persisting indefinitely. The default TTL is 5 minutes. You can adjust this using the `:ttl` option.

```elixir
use LiveStash, mode: :server, ttl: 60 * 1000,
```

## Default Settings

If you initialize LiveStash without any options, it will fall back to the following default configuration:

```elixir
[
  mode: :server,
  security_mode: :sign,
  ttl: 300_000, # 5 minutes
  secret: "live_stash"
]
```
