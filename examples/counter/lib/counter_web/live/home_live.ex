defmodule CounterWeb.HomeLive do
  use CounterWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 flex items-center justify-center p-4">
      <div class="w-full max-w-4xl">
        <h1 class="text-4xl font-bold text-center mb-8 text-base-content">Counter Examples</h1>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body items-center text-center">
              <h2 class="card-title text-2xl mb-2">Default Counter</h2>
              <p class="text-base-content/70 mb-4">
                A standard Phoenix LiveView counter that resets on page refresh
              </p>
              <.button navigate={~p"/default"} variant="primary" class="w-full">
                View Default Counter
              </.button>
            </div>
          </div>

          <div class="card bg-base-100 shadow-xl">
            <div class="card-body items-center text-center">
              <h2 class="card-title text-2xl mb-2">LiveStash Counter</h2>
              <p class="text-base-content/70 mb-4">
                A counter using LiveStash that persists state across page refreshes
              </p>
              <.button navigate={~p"/live_stash"} variant="primary" class="w-full">
                View LiveStash Counter
              </.button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
