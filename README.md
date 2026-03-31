# LiveStash

LiveStash provides a reliable, explicit API to safely stash and recover [Phoenix LiveView](https://github.com/phoenixframework/phoenix_live_view) assigns, keeping your application state completely intact whenever a socket connection is interrupted or re-established.

Check out our [documentation](https://docs.swmansion.com/live-stash/) or play around with [examples](./examples/showcase_app/README.md) to explore all capabilities in detail.

## Usage

Adding LiveStash to your existing LiveView is very simple.

1. Add `use LiveStash` to your module

```elixir
defmodule ShowcaseAppWeb.CounterLive do
  use LiveStash
```

2. Decide which part of your LiveView state you want to stash.

```elixir
  def handle_event("increment", _, socket) do
    socket
    |> assign(:count, socket.assigns.count + 1)
    |> assign(:user_id, 123)
    |> LiveStash.stash_assigns([:count, :user_id]) # pass the list of assigns that you want to stash
    |> then(&{:noreply, &1})
  end
```

2. Call `recover_state(socket)` in your `mount/3` function call. It will automatically restored assigns to your socket.

```elixir
  def mount(_params, _session, socket) do
    socket
    |> LiveStash.recover_state()
    |> case do
        {:recovered, recovered_socket} ->
          # socket with previously stashed assigns is recovered
          recovered_socket

        _ ->
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
    {:live_stash, "~> 0.1.0"}
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

## Contributing

For those planning to contribute to this project, you can run an example projects with LiveStash with following commands:

```bash
cd examples/showcase_app
mix setup
iex -S mix
```

## Authors

LiveStash is created by Software Mansion.

Since 2012 [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=livestash) is a software agency with experience in building web and mobile apps as well as complex multimedia solutions. We are Core React Native Contributors, Elixir ecosystem experts, and live streaming and broadcasting technologies specialists. We can help you build your next dream product – [Hire us](https://swmansion.com/contact/projects).

Copyright 2026, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=livestash)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=livestash-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=livestash)

Licensed under the [Apache License, Version 2.0](LICENSE)
