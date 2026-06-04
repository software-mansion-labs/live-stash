defmodule TestingWeb.LiveStashServerCounterLive do
  use TestingWeb, :live_view

  use LiveStash,
    adapter: LiveStash.Adapters.ETS,
    ttl: 2,
    stored_keys: [:count]

  def mount(_params, _session, socket) do
    socket
    |> LiveStash.recover_state()
    |> case do
      {:recovered, recovered_socket} ->
        recovered_socket

      {_, socket} ->
        assign(socket, count: 0)
    end
    |> then(&{:ok, &1})
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1>Counter (ETS)</h1>
      <div class="stat-value">{@count}</div>
      <button phx-click="decrement" aria-label="Decrement">-</button>
      <button phx-click="add_zero" aria-label="Add Zero">0</button>
      <button phx-click="increment" aria-label="Increment">+</button>
      <button phx-click="reset_stash" aria-label="Reset Stash">Reset Stash</button>
    </div>
    """
  end

  def handle_event("add_zero", _, socket) do
    socket
    |> assign(:count, socket.assigns.count + 0)
    |> LiveStash.stash()
    |> then(&{:noreply, &1})
  end

  def handle_event("increment", _, socket) do
    socket
    |> assign(:count, socket.assigns.count + 1)
    |> LiveStash.stash()
    |> then(&{:noreply, &1})
  end

  def handle_event("decrement", _, socket) do
    socket
    |> assign(:count, socket.assigns.count - 1)
    |> LiveStash.stash()
    |> then(&{:noreply, &1})
  end

  def handle_event("reset_stash", _, socket) do
    socket
    |> LiveStash.reset_stash()
    |> assign(:count, 0)
    |> then(&{:noreply, &1})
  end
end
