defmodule ShowcaseAppWeb.HomeLive do
  use ShowcaseAppWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="hero min-h-screen bg-base-300" data-theme="dark">
      <div class="hero-content text-center flex flex-col">
        <div class="max-w-2xl mb-10">
          <h1 class="text-5xl md:text-6xl font-extrabold text-transparent bg-clip-text bg-gradient-to-r from-[#4e2a8e] to-purple-400 mb-6 pb-2 drop-shadow-sm">
            Let's see what LiveStash can do!
          </h1>
          <p class="text-xl text-gray-400">
            Select a category below to test different ways of managing state and validation in Phoenix LiveView.
          </p>
        </div>

        <div class="flex flex-col sm:flex-row gap-6 justify-center w-full max-w-md">
          <.link
            navigate={~p"/tic-tac-toe"}
            class="flex-1 btn bg-[#4e2a8e] hover:bg-[#3a1f6a] text-white border-none h-auto py-6 rounded-2xl text-lg shadow-xl hover:scale-105 transition-all"
          >
            <div class="flex flex-col items-center gap-3">
              <span class="font-bold">Tic tac toe</span>
            </div>
          </.link>

          <.link
            navigate={~p"/counter"}
            class="flex-1 btn bg-[#4e2a8e] hover:bg-[#3a1f6a] text-white border-none h-auto py-6 rounded-2xl text-lg shadow-xl hover:scale-105 transition-all"
          >
            <div class="flex flex-col items-center gap-3">
              <span class="font-bold">Counters</span>
            </div>
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
