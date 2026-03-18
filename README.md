# LiveStash

LiveStash keeps LiveView state across reconnects. You can persist assigns:

- in the **browser** (client mode)
- on the **server** (server mode)

Check out our [documentation]() or play around with [examples](./examples/showcase_app/README.md) to explore all capabilities in detail.

Reconnects are not so scary anymore with LiveStash onboard!

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

## Usage

Adding LiveStash to your existing LiveView is very simple.

1. Decide which part of your LiveView state you want to stash.

```elixir
  def handle_event("increment", _, socket) do
    socket
    |> assign(:count, socket.assigns.count + 1)
    |> LiveStash.stash_assigns([:count]) # pass the socket and list of assign keys, stash_assigns/2 returns a socket so you can add it to your pipe sequence!
    |> then(&{:noreply, &1})  end
```

2. Add `use LiveStash` to your module and in your mount/3 function call recover_state(socket). There! Your LiveView state just got recovered.

```elixir
defmodule ShowcaseAppWeb.LiveStashCounterLive do
  use LiveStash # this will initialize LiveStash in on_mount/3

  def mount(_params, _session, socket) do
    socket
    |> LiveStash.recover_state() # socket with previously stashed assigns is recovered
    |> case do
        {:recovered, recovered_socket} ->
          recovered_socket

        _ ->
          assign(socket, count: 0)
    end
    |> then(&{:ok, &1})
  end
```

## Optional configuration

See [Configuration Guide]() for details on how to customize LiveStash to your needs.

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
