# Configuration

This section covers the shared configuration options. For mode-specific settings, please refer to the respective documentation pages:

- **[Client](./client.md)**
- **[Server](./server.md)**

LiveStash is configured on a per live view basis by passing options directly to the `use LiveStash` macro.

```elixir
use LiveStash, mode: :client, security_mode: :encrypt, session_key: "user_token"
```

## Storage mode

You can control where the stashed data is kept using the `:mode` option. LiveStash supports two modes:

- **Server** (default) - The data is kept on the server side.
- **Client** - The data is saved in the client browser.

```elixir
use LiveStash, mode: :client
```

## Security

By default, LiveStash uses a hardcoded default secret (`"live_stash"`) to secure your data. For production environments, it is highly recommended to tie the stash to a specific user session to prevent tampering or data leakage.

You can do this by providing a `:session_key`. LiveStash will extract the value from the connection session securely hash it (SHA-256) to use as the operational secret. If you provide the key and it is not present in the session, `Argument Error` will be raised.

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
