defmodule ShowcaseAppWeb.E2eTest.MnesiaClusterController do
  @moduledoc false

  use ShowcaseAppWeb, :controller

  @table LiveStash.Adapters.Mnesia.State
  @storage LiveStash.Adapters.Mnesia.Storage
  @valid_remotes ~w(a@node_a b@node_b)

  def info(conn, _params) do
    json(conn, %{
      node: to_string(node()),
      connected_nodes: Enum.map(Node.list(), &to_string/1),
      mnesia_running: :mnesia.system_info(:is_running) == :yes,
      table_size: safe_table_info(:size),
      where_to_read: safe_table_info(:where_to_read) |> inspect()
    })
  end

  def poison(conn, _params) do
    poison_id = "poison_pill_#{System.unique_integer([:positive])}"
    poison_record = {@table, poison_id, self(), System.os_time(:second) + 3600, %{}}

    :ets.insert(@table, poison_record)

    json(conn, %{ok: true, injected_id: poison_id})
  end

  def simulate_inconsistency(conn, %{"from" => remote}) when remote in @valid_remotes do
    remote_atom = String.to_existing_atom(remote)

    case Process.whereis(@storage) do
      nil ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "storage not running"})

      pid ->
        send(pid, {:mnesia_system_event, {:inconsistent_database, :e2e_test, remote_atom}})
        json(conn, %{ok: true, from: remote, target: to_string(node())})
    end
  end

  def simulate_inconsistency(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid or missing 'from' parameter"})
  end

  defp safe_table_info(key) do
    :mnesia.table_info(@table, key)
  rescue
    _ -> nil
  end
end
