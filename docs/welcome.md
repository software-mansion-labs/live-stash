# Welcome to LiveStash

LiveStash provides a reliable, explicit API to safely stash and recover [Phoenix LiveView](https://github.com/phoenixframework/phoenix_live_view) assigns, keeping your application state completely intact whenever a socket connection is interrupted or re-established.

## Usage

Adding LiveStash to your existing LiveView is very simple.

1. Add `use LiveStash` to your module. It registers LiveStash's `on_mount` hook, which initializes stash support for the socket.
   See [`LiveStash.__using__/1`](LiveStash.html#__using__/1).

The assigns you want to persist are declared once at the module level with `stored_keys: [...]`.

```elixir
defmodule ShowcaseAppWeb.CounterLive do
  use LiveStash, stored_keys: [:count, :user_id]
```

2. Update your assigns and call `LiveStash.stash/1`. The assigns you declared in the previous step will be persisted. LiveStash avoids redundant stash writes when the values have not changed.

```elixir
  def handle_event("increment", _, socket) do
    socket
    |> assign(:count, socket.assigns.count + 1)
    |> assign(:user_id, 123)
    |> LiveStash.stash()
    |> then(&{:noreply, &1})
  end
```

3. Call `recover_state(socket)` in your `mount/3` function call. It will automatically restore assigns to your socket.

```elixir
  def mount(_params, _session, socket) do
    socket
    |> LiveStash.recover_state()
    |> case do
        {:recovered, recovered_socket} ->
          # socket with previously stashed assigns is recovered
          recovered_socket

        {_, socket} ->
          # could not recover assigns, proceed with standard setup using returned socket
          # ...
    end
    |> then(&{:ok, &1})
  end
```

## Installation

Add `live_stash` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:live_stash, "~> 0.2.0"}
  ]
end
```

In your `app.js`, pass `initLiveStash` into the LiveSocket params:

```javascript
import initLiveStash from "../../deps/live_stash/assets/js/live-stash.js";

const liveSocket = new LiveSocket("/live", Socket, {
  params: initLiveStash({ _csrf_token: csrfToken }),
  // ...
});
```

## Storage modes

You can control where the stashed data is kept by passing appropriate adapter module. LiveStash currently supports two adapters:

- **ETS** - (default) The data is kept on the server side in the ETS table.
- **Browser memory** - The data is saved in the client browser.

```elixir
use LiveStash, adapter: LiveStash.Adapters.ETS, stored_keys: [:count, :user_id]
```

Remember to define adapters you would like to activate in your `config.exs` file.

```elixir
config :live_stash, adapters: [LiveStash.Adapters.ETS, LiveStash.Adapters.BrowserMemory]
```

The default adapter is `LiveStash.Adapters.ETS` and it is always activated.

See [ETS Adapter Guide](./ets.md) and [Browser Memory Adapter Guide](./browser_memory.md) for details on how to customize LiveStash to your needs.

## When not to use

LiveStash is meant for **explicitly stashing server-side LiveView assigns** that you truly need to survive reconnects. For a lot of state, there are better (and simpler) tools:

- **Pure UI toggles and ephemeral client state**: For things like opening a modal, toggling a dropdown, or highlighting a row, prefer keeping the state on the client with [`Phoenix.LiveView.JS`](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html). For more complex interactions, use [`phx-hook`](https://hexdocs.pm/phoenix_live_view/js-interop.html#client-hooks-via-phx-hook) to manage state locally in the browser.
- **Form inputs**: LiveView includes built-in form auto-recovery that replays the form data after reconnect. If your main concern is users losing typed input, you likely don’t need LiveStash. See [How Phoenix LiveView Form Auto-Recovery works](https://fly.io/phoenix-files/how-phoenix-liveview-form-auto-recovery-works/).
- **Navigation/context state**: For pagination, filters, sorting, and search terms, put the state in URL query params. This is the most resilient approach across reloads, reconnects, and shareable links.

## Authors

LiveStash is created by Software Mansion.

Since 2012 [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=livestash) is a software agency with experience in building web and mobile apps as well as complex multimedia solutions. We are Core React Native Contributors, Elixir ecosystem experts, and live streaming and broadcasting technologies specialists. We can help you build your next dream product – [Hire us](https://swmansion.com/contact/projects).

Copyright 2026, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=livestash)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=livestash-hexdocs)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=livestash)
