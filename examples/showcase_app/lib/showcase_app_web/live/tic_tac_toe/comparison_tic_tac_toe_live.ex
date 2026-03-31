defmodule ShowcaseAppWeb.ComparisonTicTacToeLive do
  use ShowcaseAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-300 py-10 px-4" data-theme="dark">
      <div class="max-w-[1400px] mx-auto">
        <div class="flex flex-col items-center mb-8">
          <h1 class="text-4xl font-bold text-white mb-2">LiveStash vs Standard: State Persistence Comparison</h1>
          <p class="text-gray-400">Test the state recovery after reconnect</p>
          <div class="mt-4">
            <.return_link />
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 h-[850px]">

          <div class="flex flex-col rounded-3xl overflow-hidden shadow-2xl border-2 border-gray-700 bg-base-100 transition-all hover:border-[#4e2a8e]">
            <div class="bg-gray-900 text-center py-4 font-bold text-purple-400 tracking-wide uppercase text-sm">
              Version with LiveStash
            </div>
            <iframe
              src="/tic-tac-toe/live_stash_client?embed=true"
              class="w-full h-full border-none"
              title="LiveStash Tic Tac Toe">
            </iframe>
          </div>

          <div class="flex flex-col rounded-3xl overflow-hidden shadow-2xl border-2 border-gray-700 bg-base-100 transition-all hover:border-blue-500">
            <div class="bg-gray-900 text-center py-4 font-bold text-blue-400 tracking-wide uppercase text-sm">
              Plain Version
            </div>
            <iframe
              src="/tic-tac-toe/default?embed=true"
              class="w-full h-full border-none"
              title="Default Tic Tac Toe">
            </iframe>
          </div>

        </div>
      </div>
    </div>
    """
  end
end
