defmodule LiveStash.Server do
  @moduledoc """
  A server-side stash that persists data in the server's memory.
  """

  @behaviour LiveStash.Stash

  alias LiveStash.Server.State
  alias LiveStash.Utils

  alias Phoenix.LiveView

  require Logger

  @impl true
  def init_stash(socket, opts) do
    ttl = Keyword.fetch!(opts, :ttl)
    mounts = LiveView.get_connect_params(socket)["_mounts"]
    reconnected? = not is_nil(mounts) and mounts > 0

    # If mounts is set to 0 we are on a new connection and stashed state is no longer valid
    if not reconnected? do
      socket
      |> get_id()
      |> State.delete_by_id!()
    end

    socket
    |> LiveView.put_private(:live_stash_mode, :server)
    |> LiveView.put_private(:live_stash_ttl, ttl)
    |> LiveView.put_private(:live_stash_reconnected?, reconnected?)
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

    case get_state_from_cluster!(id) do
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
    |> get_id()
    |> State.delete_by_id!()

    socket
  rescue
    error ->
      err = Utils.error_message("Could not reset stash", error, __STACKTRACE__)
      Logger.error(err)

      socket
  end

  defp get_state_from_cluster!(id) do
    case State.get_by_id!(id) do
      {:ok, state} ->
        {:ok, state}

      :not_found ->
        search_in_other_nodes(id)
    end
  end

  defp search_in_other_nodes(id) do
    nodes = Node.list()

    recovery_result =
      if Enum.empty?(nodes) do
        :not_found
      else
        results = :erpc.multicall(nodes, State, :get_by_id!, [id])

        nodes_with_results = Enum.zip(nodes, results)

        Enum.find_value(nodes_with_results, fn
          {_node, {:ok, {:ok, state}}} ->
            {:ok, state}

          {_node, {:ok, :not_found}} ->
            nil

          {node, {:error, {:exception, error, stacktrace}}} ->
            msg =
              Utils.error_message(
                "Exception on node #{inspect(node)} for id #{inspect(id)}",
                error,
                stacktrace
              )

            Logger.error(msg)
            nil

          {node, error} ->
            Logger.error("RPC communication error with node #{inspect(node)}: #{inspect(error)}")
            nil
        end)
      end

    recovery_result || :not_found
  end

  defp get_id(socket) do
    socket.id
  end

  defp get_opts(socket) do
    [ttl: socket.private.live_stash_ttl]
  end
end
