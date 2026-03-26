# Welcome to LiveStash

LiveStash provides a reliable, explicit API to safely stash and recover [Phoenix LiveView](https://github.com/phoenixframework/phoenix_live_view) assigns, keeping your application state completely intact whenever a socket connection is interrupted or re-established.

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

## Optional configuration

### Storage mode

You can control where the stashed data is kept by passing appropiate adapter module. LiveStash currently supports two adapters:

- **ETS** - The data is kept on the server side in the ETS table.
- **Browser memory** (default) - The data is saved in the client browser.

```elixir
use LiveStash, adapters: LiveStash.Adapters.ETS
```

Remember to define adapters you would like to activate in your `config.exs` file.

```elixir
config :live_stash, adapters: [LiveStash.Adapters.ETS, LiveStash.Adapters.BrowserMemory]
```

The default adapter is `LiveStash.Adapters.BrowserMemory` and it is always activated.

See [ETS Adapter Guide](./ets.md) and [Browser Memory Adapter Guide](./browser_memory.md) for details on how to customize LiveStash to your needs.

## Authors

LiveStash is created by Software Mansion.

Since 2012 [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=livestash) is a software agency with experience in building web and mobile apps as well as complex multimedia solutions. We are Core React Native Contributors, Elixir ecosystem experts, and live streaming and broadcasting technologies specialists. We can help you build your next dream product – [Hire us](https://swmansion.com/contact/projects).

Copyright 2026, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=livestash)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=livestash-hexdocs)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=livestash)
