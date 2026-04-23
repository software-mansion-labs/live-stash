defmodule LiveStash.Component do
  defmacro __using__(_opts) do
    quote do
      def update(assigns, socket) do
        socket =
          socket
          |> assign(assigns)
          |> LiveStash.Component.inject_stash_recovery()

        {:ok, socket}
      end

      defoverridable update: 2
    end
  end

  @doc false
  def inject_stash_recovery(socket) do
    if socket.assigns[:__live_stash_recovered__] do
      socket
    else
      stashed_state = socket.assigns[:recovered_state] || %{}

      socket
      |> Phoenix.Component.assign(:__live_stash_recovered__, true)
      |> Phoenix.Component.assign(stashed_state)
    end
  end
end

defmodule ShowcaseAppWeb.MyCounterComponent do
  use Phoenix.LiveComponent
  use LiveStash.Component

  def update(assigns, socket) do
    {:ok, socket} = super(assigns, socket)

    {:ok, assign(socket, :inna_zmienna, 123)}
  end

  # def render(assigns) do ... end
end
