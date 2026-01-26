defmodule LiveStash.Server do
  @moduledoc """
  A server-side stash that persists data in the server's memory.
  """

  @behaviour LiveStash.Stash

  alias Phoenix.LiveView
  alias Phoenix.Component
  alias LiveStash.Server.State

  require Logger

  @impl true
  def init_stash(socket, opts) do
    ttl = Keyword.fetch!(opts, :ttl)
    mounts = LiveView.get_connect_params(socket)["_mounts"]
    reconnected? = not is_nil(mounts) and mounts > 0

    socket
    |> LiveView.put_private(:live_stash_mode, :server)
    |> LiveView.put_private(:live_stash_ttl, ttl)
    |> LiveView.put_private(:live_stash_reconnected?, reconnected?)
  end

  @impl true
  def stash_assign(socket, key, value) do
    id = get_id(socket)

    State.put_assign!(id, key, value, get_opts(socket))
    Component.assign(socket, key, value)
  end

  @impl true
  def recover_state(socket) do
    id = get_id(socket)

    case State.get_by_id!(id) do
      {:ok, state} ->
        {:recovered, Component.assign(socket, state)}

      :not_found ->
        {:not_found, socket}
    end
  end

  defp get_id(socket) do
    socket.id
  end

  defp get_opts(socket) do
    [ttl: socket.private.live_stash_ttl]
  end
end
