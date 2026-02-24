defmodule ShowcaseAppWeb.HomeLive do
  use ShowcaseAppWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="hero min-h-screen bg-base-300" data-theme="dark">
      <div class="hero-content text-center">
        <div class="max-w-md">
          <h1 class="text-5xl font-bold text-white mb-8">
            Welcome
          </h1>

          <.link
            navigate={~p"/register"}
            class="btn bg-[#4e2a8e] hover:bg-[#3a1f6a] text-white border-none px-8 text-lg"
          >
            Join
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
