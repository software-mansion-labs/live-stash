defmodule ShowcaseAppWeb.E2eTest.CounterComponent do
  use ShowcaseAppWeb, :live_component
  use LiveStash.Component, stored_keys: [:component_count]

  def mount(socket) do
    {:ok, assign(socket, :component_count, 0)}
  end

  def render(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl w-full max-w-md mt-6" data-testid="counter-component">
      <div class="card-body items-center text-center">
        <h2 class="card-title text-2xl mb-2">Component Counter</h2>

        <div class="bg-base-200 rounded-lg px-8 py-4 my-4">
          <div
            class="text-4xl font-bold text-secondary"
            data-testid="component-count"
          >
            {@component_count}
          </div>
          <div class="text-sm opacity-70">Component Count</div>
        </div>

        <div class="card-actions justify-center gap-4 mt-2">
          <button
            phx-click="component_decrement"
            phx-target={@myself}
            class="btn btn-circle btn-outline btn-error"
            aria-label="Component Minus"
          >
            -
          </button>
          <button
            phx-click="component_increment"
            phx-target={@myself}
            class="btn btn-circle btn-secondary"
            aria-label="Component Plus"
          >
            +
          </button>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("component_increment", _, socket) do
    socket
    |> assign(:component_count, socket.assigns.component_count + 1)
    |> LiveStash.Component.stash()
    |> then(&{:noreply, &1})
  end

  def handle_event("component_decrement", _, socket) do
    socket
    |> assign(:component_count, socket.assigns.component_count - 1)
    |> LiveStash.Component.stash()
    |> then(&{:noreply, &1})
  end
end
