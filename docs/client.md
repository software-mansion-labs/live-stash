# Client

## Description

In `:client` mode, the stashed state is kept in the browser's memory. Each call to `stash_assigns/2` pushes assigns to the client via `Phoenix.LiveView.push_event/3`, storing them in a JavaScript variable. Upon LiveView reconnection, the client automatically sends this state back to the server via connection parameters.

## When to use

- **Frequent deployments:** Ideal for preserving state across server restarts. Unlike the `:server` mode, client-side state survives application downtime and redeploys.
- **Lightweight payloads:** Since the state is synchronized over WebSockets on every stash operation, restrict usage to small data structures to minimize network overhead and latency.
- **Non-sensitive data:** The payload is always cryptographically signed to prevent client-side tampering, and can optionally be encrypted. Keep in mind that unless encryption is explicitly enabled, the data remains readable in the browser's memory, so avoid stashing sensitive information in plaintext.

### State recovery

An updated socket is returned from `LiveStash.recover_state/1` only if **every** key-value pair from the signed list of stashed keys was succesfully recovered.

### Reseting the stash

The stash is always cleared after a LiveView using **client** mode is rendered for the first time. You can also do it manually with `LiveStash.reset_stash/1`. Naturally, refreshing the browser tab clears this state as well.

## Security

### Session key

By default, LiveStash uses a hardcoded default secret (`"live_stash"`) to secure your data. For production environments, it is highly recommended to tie the stash to a specific user session to prevent tampering or data leakage.

You can do this by providing a `:session_key`. LiveStash will extract the value from the connection session securely hash it (SHA-256) to use as the operational secret. If you provide the key and it is not present in the session, `Argument Error` will be raised.

### Security mode

In client mode, the secret defined in the **general configuration** is used as part of the key to sign or encrypt your stashed state, which is stored in the browser.

Additionally, you can configure how the data is secured in client mode using the `:security_mode` option. It defaults to `:sign`, but can be set to `:encrypt` for sensitive payloads.

```elixir
use LiveStash, mode: :client, security_mode: :encrypt
```
