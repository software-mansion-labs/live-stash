# LiveStash

LiveStash keeps LiveView state across reconnects. You can persist assigns in the **browser** (client mode) or on the **server** (server mode).

## Installation

Add `live_stash` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:live_stash, "~> 0.1.0"}
  ]
end
```

In your `app.js` (or equivalent), pass `initLiveStash` into the LiveSocket params:

```javascript
import initLiveStash from "../deps/live_stash/priv/static/live-stash.js";

const liveSocket = new LiveSocket("/live", Socket, {
  params: initLiveStash({ _csrf_token: csrfToken }),
  // ...
});
```
