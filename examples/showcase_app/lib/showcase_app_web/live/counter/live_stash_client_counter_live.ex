defmodule ShowcaseAppWeb.LiveStashClientCounterLive do
  use ShowcaseAppWeb, :live_view
  use LiveStash, mode: :client, security_mode: :encrypt

  import LiveStash

  def mount(_params, _session, socket) do
    socket
    |> recover_state()
    |> case do
        {:recovered, %{count: count}} ->
          socket
          |> stash(:count, count)
          |> assign(count: count)

        _ ->
          socket
          |> stash(:count, 0)
          |> assign(count: 0)
    end
    |> then(&{:ok, &1})
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 flex items-center justify-center p-4">
      <div class="card bg-base-100 shadow-xl w-full max-w-md">
        <.return_link />

        <div class="card-body items-center text-center">
          <h1 class="card-title text-4xl mb-2">Counter</h1>

          <div class="stat bg-base-200 rounded-lg px-8 py-4 my-4">
            <div class="stat-value text-6xl font-bold text-primary">{@count}</div>
            <div class="stat-title text-sm opacity-70">Current Count</div>
          </div>

          <div class="card-actions justify-center gap-4 mt-4">
            <button
              phx-click="decrement"
              class="btn btn-circle btn-lg btn-outline btn-error"
              aria-label="Decrement"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
                class="w-6 h-6"
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 12h-15" />
              </svg>
            </button>

            <button
              phx-click="increment"
              class="btn btn-circle btn-lg btn-primary"
              aria-label="Increment"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
                class="w-6 h-6"
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
              </svg>
            </button>
          </div>
        </div>
      </div>
      <.socket_debugger />
    </div>
    """
  end

  def handle_event("increment", _, socket) do
    socket
    |> stash(:count, socket.assigns.count + 1)
    |> assign(:count, socket.assigns.count + 1)
    |> then(&{:noreply, &1})
  end

  def handle_event("decrement", _, socket) do
    socket
    |> stash(:count, socket.assigns.count - 1)
    |> assign(:count, socket.assigns.count - 1)
    |> then(&{:noreply, &1})
  end
end
