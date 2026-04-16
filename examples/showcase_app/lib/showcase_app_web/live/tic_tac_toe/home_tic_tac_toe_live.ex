defmodule ShowcaseAppWeb.HomeTicTacToeLive do
  use ShowcaseAppWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center py-12 px-6">
      <div class="w-full max-w-6xl">
        <div class="flex justify-between items-center mb-10">
          <h1 class="text-4xl font-bold text-white">Tic Tac Toe Examples</h1>

          <.return_link />
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <.feature_card
            title="Default Tic Tac Toe"
            navigate={~p"/tic-tac-toe/default"}
            button_text="View Default Tic Tac Toe"
          >
            A standard Phoenix LiveView Tic Tac Toe game that resets on page refresh.
          </.feature_card>

          <.feature_card
            title="LiveStash Server"
            navigate={~p"/tic-tac-toe/live_stash_server"}
            button_text="View Server Tic Tac Toe"
          >
            A Tic Tac Toe game using LiveStash server mode that persists state across page refreshes.
          </.feature_card>

          <.feature_card
            title="LiveStash Client Auth"
            navigate={~p"/auth/tic-tac-toe/live_stash_client"}
            button_text="View Client Tic Tac Toe"
          >
            A Tic Tac Toe game using LiveStash client mode with authentication.
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
