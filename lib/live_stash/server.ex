defmodule LiveStash.Server do
  @moduledoc """
  A server-side stash that persists data in the server's memory.
  """

  @behaviour LiveStash.Stash

  alias LiveStash.Server.NodeHint
  alias LiveStash.Server.State
  alias LiveStash.Server.StateFinder
  alias LiveStash.Utils

  require Logger

  @impl true
  def init_stash(socket, _session, _opts) do
    reconnected? = socket.private.live_stash.reconnected?

    stash_id = fetch_stash_id(socket)

    {socket, id} =
      if is_nil(stash_id) do
        new_id = UUID.uuid4()

        updated_socket =
          Phoenix.LiveView.push_event(socket, "live-stash:stash-id", %{"stashId" => new_id})

        {updated_socket, new_id}
      else
        {socket, stash_id}
      end

    socket = Phoenix.LiveView.put_private(socket, :live_stash_id, id)

    if not reconnected? do
      socket
      |> get_ets_id()
      |> State.delete_by_id!()
    end

    NodeHint.save_node_hint(socket)
  end

  defp fetch_stash_id(socket) do
    case Phoenix.LiveView.get_connect_params(socket) do
      %{"stashId" => id} when is_binary(id) ->
        id

      _ ->
        nil
    end
  end

  defp get_ets_id(socket) do
    id = socket.private.live_stash_id
    secret = socket.private.live_stash.secret

    raw_key = id <> secret
    hashed_binary = :crypto.hash(:sha256, raw_key)

    Base.encode64(hashed_binary, padding: false)
  end

  @impl true
  def stash(socket, key, value) do
    socket
    |> get_ets_id()
    |> State.put!(key, value, get_opts(socket))

    socket
  rescue
    error ->
      err = Utils.error_message("Could not stash assign", error, __STACKTRACE__)
      Logger.error(err)

      socket
  end

  @impl true
  def recover_state(socket) do
    id = get_ets_id(socket)
    node_hint = socket.private.live_stash.node_hint

    case StateFinder.get_from_cluster(id, node_hint) do
      {:ok, state} ->
        {:recovered, state}

      :not_found ->
        {:not_found, %{}}
    end
  rescue
    error ->
      err = Utils.error_message("Could not recover state", error, __STACKTRACE__)
      Logger.error(err)

      {:error, err}
  end

  @impl true
  def reset_stash(socket) do
    socket
    |> get_ets_id()
    |> State.delete_by_id!()

    socket
  rescue
    error ->
      err = Utils.error_message("Could not reset stash", error, __STACKTRACE__)
      Logger.error(err)

      socket
  end

  defp get_opts(socket) do
    [ttl: socket.private.live_stash.ttl]
  end
end
