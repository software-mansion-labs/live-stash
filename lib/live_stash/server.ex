defmodule LiveStash.Server do
  @moduledoc """
  A server-side stash that persists data in the server's memory.
  """

  @behaviour LiveStash.Stash

  alias Phoenix.LiveView
  alias Phoenix.Component
  alias LiveStash.Server.Storage

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

    id
    |> Storage.put_state(key, value)
    |> case do
      :ok ->
        socket

      {:error, error} ->
        Logger.error(
          "[LiveStash] Failed to put state for LiveView with id: #{id}\n#{inspect(error)}"
        )

        socket
    end
    |> Component.assign(key, value)
  end

  @impl true
  def recover_state(socket) do
    id = get_id(socket)

    id
    |> Storage.get_state()
    |> case do
      {:ok, state} ->
        {:recovered, Component.assign(socket, state)}

      {:error, :not_found} ->
        {:not_found, socket}

      {:error, error} ->
        Logger.error(
          "[LiveStash] Failed to recover state for LiveView with id: #{id}\n#{inspect(error)}"
        )

        {:error, socket}
    end
  end

  defp get_id(socket) do
    socket.id
  end
end
