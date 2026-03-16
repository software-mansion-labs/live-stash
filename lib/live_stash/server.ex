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

    # If mounts is set to 0 we are on a new connection and stashed state is no longer valid
    if not reconnected? do
      socket
      |> get_id()
      |> State.delete_by_id!()
    end

    NodeHint.save_node_hint(socket)
  end

  @impl true
  def stash(socket, key, value) do
    socket
    |> get_id()
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
    id = get_id(socket)
    node_hint = socket.private.live_stash.node_hint

    case StateFinder.get_from_cluster(id, node_hint) do
      {:ok, recovered_state} ->
        {:recovered, recovered_state}

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
    |> get_id()
    |> State.delete_by_id!()

    socket
  rescue
    error ->
      err = Utils.error_message("Could not reset stash", error, __STACKTRACE__)
      Logger.error(err)

      socket
  end

  defp get_id(%{id: id, private: %{live_stash: %LiveStash.Settings{secret: secret}}} = _socket)
       when is_binary(id) and is_binary(secret) do
    raw_key = id <> secret
    hashed_binary = :crypto.hash(:sha256, raw_key)

    Base.encode64(hashed_binary, padding: false)
  end

  defp get_opts(socket) do
    [ttl: socket.private.live_stash.ttl]
  end
end
