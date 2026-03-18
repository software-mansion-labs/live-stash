# Client

## Description

In client mode, the stashed state is saved to the browser memory through `Phoenix.LiveView.push_event/3`.

### Stash structure

State is saved in the following form after `LiveStash.stash_assigns/2` is called:

```javascript
stashedState:{
    "assigns":{
        "encoded_key_1": "signed_or_encrypted_value1",
        "encoded_key_2": "signed_or_encrypted_value2",
    },
    "keys": "signed_or_encrypted_list_of_stashed_keys"
}
```

### State recovery

An updated socket is returned from `LiveStash.recover_state/1` only if **every** key-value pair from the signed list of stashed keys was succesfully recovered.

### Reseting the stash

The stash is always cleared after a LiveView using **client** mode is rendered for the first time. You can also do it manually with `LiveStash.reset_stash/1`. Naturally, refreshing the browser tab clears this state as well.

## Configuration

### Security

In client mode, the secret defined in the **general configuration** is used as part of the key to sign or encrypt your stashed state, which is stored in the browser.

Additionally, you can configure how the data is secured in client mode using the `:security_mode` option. It defaults to `:sign`, but can be set to `:encrypt` for sensitive payloads.

```elixir
use LiveStash, mode: :client, security_mode: :encrypt
```
