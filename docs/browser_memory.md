# Browser memory

## Description

In this mode, the stashed state is kept in the browser's memory. Each call to `stash/1` pushes the configured assigns to the client via `Phoenix.LiveView.push_event/3`, storing them in a JavaScript variable. Upon LiveView reconnection, the client automatically sends this state back to the server via connection parameters.

The assigns you want to persist are declared once at the module level with `stored_keys: [...]`, and `stash/1` only sends the state to the client if those values have changed since the last stash.

LiveStash requires you to call `LiveStash.stash/1` manually by default (`auto_stash: false`). Set `auto_stash: true` if you prefer to auto-stash after each render.

## When to use

Choose the Browser Memory mode when:

- **Frequent deployments:** Ideal for preserving state across server restarts. Unlike the ETS mode, client-side state survives application downtime and redeploys.
- **Lightweight payloads:** Since the state is synchronized over WebSockets on every stash operation, restrict usage to small data structures to minimize network overhead and latency.
- **Non-sensitive data:** The payload is always cryptographically signed to prevent client-side tampering, and can optionally be encrypted. Keep in mind that unless encryption is explicitly enabled, the data remains readable in the browser's memory, so avoid stashing sensitive information in plaintext.
- **Larger TTL** Moving state from the server to the user's browser offloads your server memory, allowing you to stash your assigns for a longer time.

### State recovery

An updated socket is returned from `LiveStash.recover_state/1` only if the stored browser token can be successfully decoded and applied. The recovered state is the exact map that was previously serialized during `stash/1`.

### Reseting the stash

The stash is always cleared after a LiveView using this mode is rendered for the first time. You can also do it manually with `LiveStash.reset_stash/1`. Naturally, refreshing the browser tab clears this state as well.

## Configuration

### Expiration (TTL)

Stashed data has a Time-To-Live (TTL) that is used to determine how long the data should be retained. You can adjust this using the `:ttl` option. There is an external upper limit from Phoenix Token of 1 day (24 hours) for the maximum TTL.

**Default:** `300` seconds (5 minutes)

```elixir
use LiveStash, adapter: LiveStash.Adapters.BrowserMemory, ttl: 60, stored_keys: [:count]
```

## Security

### Session key

By default, LiveStash uses a hardcoded default secret (`"live_stash"`) to secure your data. For production environments, it is highly recommended to tie the stash to a specific user session to prevent tampering or data leakage.

You can do this by providing a `:session_key`. LiveStash will extract the value from the connection session securely hash it (SHA-256) to use as the operational secret. If you provide the key and it is not present in the session, `Argument Error` will be raised.

```elixir
use LiveStash, adapter: LiveStash.Adapters.BrowserMemory, session_key: "user_token", stored_keys: [:count]
```

### Security mode

In browser mode, the secret defined in the configuration section is used as part of the key to sign or encrypt your stashed state, which is stored in the browser.

Additionally, you can configure how the data is secured in client mode using the `:security_mode` option. It defaults to `:sign`, but can be set to `:encrypt` for sensitive payloads.

```elixir
use LiveStash, adapter: LiveStash.Adapters.BrowserMemory, security_mode: :encrypt, stored_keys: [:count]
```
