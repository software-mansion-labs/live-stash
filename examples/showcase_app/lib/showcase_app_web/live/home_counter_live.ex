defmodule ShowcaseAppWeb.HomeCounterLive do
  use ShowcaseAppWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-300 flex flex-col items-center py-12 px-6" data-theme="dark">
      <div class="w-full max-w-6xl">
        <div class="flex justify-between items-center mb-10">
          <h1 class="text-4xl font-bold text-white">Counter Examples</h1>

          <.return_link />
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <.feature_card
            title="Default Counter"
            navigate={~p"/counter/default"}
            button_text="View Default Counter"
          >
            A standard Phoenix LiveView counter that resets on page refresh.
          </.feature_card>

          <.feature_card
            title="LiveStash Server"
            navigate={~p"/counter/live_stash_server"}
            button_text="View Server Counter"
          >
            A counter using LiveStash server mode that persists state across page refreshes.
          </.feature_card>

          <.feature_card
            title="LiveStash Client"
            navigate={~p"/counter/live_stash_client"}
            button_text="View Client Counter"
          >
            A counter using LiveStash client mode that persists state in the browser.
          </.feature_card>
        </div>
      </div>
    </div>
    """
  end

  def feature_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl p-6 shadow-xl flex flex-col justify-between border border-gray-800 hover:border-[#4e2a8e] transition-colors">
      <div>
        <h2 class="text-xl font-bold text-white mb-2">{@title}</h2>
        <p class="text-gray-400 text-sm mb-6">
          {render_slot(@inner_block)}
        </p>
      </div>
      <.link
        navigate={@navigate}
        class="btn bg-[#4e2a8e] hover:bg-[#3a1f6a] text-white border-none w-full"
      >
        {@button_text}
      </.link>
    </div>
    """
  end
end
