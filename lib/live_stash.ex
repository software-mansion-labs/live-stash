defmodule LiveStash do
  @moduledoc """

  LiveStash is a library that fixes problem of losing state on LiveView reconnects.
  It allows you to store and retrieve data in a LiveView application.
  """

  @behaviour LiveStash.Adapter

  alias Phoenix.LiveView
  alias LiveStash.Utils

  require Logger

  defmacro __using__(opts) do
    quote do
      on_mount({LiveStash, unquote(opts)})
    end
  end

  def on_mount(opts, _params, session, socket) do
    socket = init_stash(socket, session, opts)

    {:cont, socket}
  end

  def init_stash(socket, session, opts \\ []) do
    {adapter, opts} = Keyword.pop!(opts, :adapter)

    socket
    |> LiveView.put_private(:live_stash_adapter, adapter)
    |> adapter.init_stash(session, opts)
  end

  def stash_assigns(socket, keys) when is_list(keys) do
    socket
    |> get_adapter()
    |> apply(:stash_assigns, [socket, keys])
  end

  def stash_assigns(_socket, _keys) do
    msg =
      Utils.reason_message(
        "Keys must be a list of atoms",
        :invalid
      )

    raise ArgumentError, msg
  end

  def recover_state(socket) do
    socket
    |> get_adapter()
    |> apply(:recover_state, [socket])
  end

  def reset_stash(socket) do
    socket
    |> get_adapter()
    |> apply(:reset_stash, [socket])
  end

  defp get_adapter(%{private: %{live_stash_adapter: adapter}}), do: adapter

  defp get_adapter(_) do
    msg =
      Utils.reason_message(
        "LiveStash has not been initialized, please use on_mount/1 to initialize it",
        :error
      )

    raise ArgumentError, msg
  end
end
