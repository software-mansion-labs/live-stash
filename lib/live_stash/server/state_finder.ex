defmodule LiveStash.Server.StateFinder do
  @moduledoc """
  Finds LiveStash state in the cluster: local ETS, optional node hint, then remaining nodes via multicall.
  """

  alias LiveStash.Server.State
  alias LiveStash.Utils

  require Logger

  @doc """
  Looks up state by id, trying current node, then node_hint (if any), then other nodes.
  Returns `{:ok, state}` or `:not_found`.
  """
  @spec get_from_cluster(term(), node() | nil) :: {:ok, map()} | :not_found
  def get_from_cluster(id, node_hint) do
    with :not_found <- get_local(id),
         :not_found <- get_from_node_hint(id, node_hint) do
      get_from_other_nodes(id, node_hint)
    end
  end

  defp get_local(id) do
    State.get_by_id!(id)
  end

  defp get_from_node_hint(_id, nil), do: :not_found

  defp get_from_node_hint(id, node_hint) do
    if node_hint != Node.self() and node_hint in Node.list() do
      try do
        :erpc.call(node_hint, State, :pop_by_id!, [id])
      rescue
        error ->
          log_rpc_error(
            node_hint,
            id,
            "Exception during node_hint RPC",
            {:error, {:exception, error, __STACKTRACE__}}
          )

          :not_found
      end
    else
      :not_found
    end
  end

  defp get_from_other_nodes(id, node_hint) do
    nodes_to_ask = if node_hint, do: Node.list() -- [node_hint], else: Node.list()

    case nodes_to_ask do
      [] ->
        :not_found

      nodes ->
        results = :erpc.multicall(nodes, State, :pop_by_id!, [id])

        nodes
        |> Enum.zip(results)
        |> Enum.find_value(&handle_search_result(&1, id))
        |> Kernel.||(:not_found)
    end
  end

  defp handle_search_result({_node, {:ok, {:ok, state}}}, _id), do: {:ok, state}
  defp handle_search_result({_node, {:ok, :not_found}}, _id), do: nil

  defp handle_search_result({node, error_payload}, id) do
    log_rpc_error(node, id, "Exception during search", error_payload)
    nil
  end

  defp log_rpc_error(
         _node,
         _id,
         _context_msg,
         {:error, {:exception, %UndefinedFunctionError{}, _stacktrace}}
       ) do
    :ok
  end

  defp log_rpc_error(_node, _id, _context_msg, {:error, {:exception, :undef, _stacktrace}}) do
    :ok
  end

  defp log_rpc_error(node, id, context_msg, {:error, {:exception, error, stacktrace}}) do
    msg =
      Utils.exception_message(
        "#{context_msg} on node #{inspect(node)} for id #{inspect(id)}",
        error,
        stacktrace
      )

    Logger.error(msg)
  end

  defp log_rpc_error(node, _id, context_msg, rpc_error) do
    err =
      Utils.exception_message("RPC error (#{context_msg}) with node #{inspect(node)}", rpc_error)

    Logger.error(err)
  end
end
