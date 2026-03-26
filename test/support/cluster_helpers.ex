defmodule LiveStash.TestSupport.ClusterHelpers do
  @moduledoc false

  alias LiveStash.Adapters.ETS.State

  def ensure_distribution_started! do
    unless Node.alive?() do
      if epmd = System.find_executable("epmd") do
        _ = System.cmd(epmd, ["-daemon"])
      end

      name = :"live_stash_test_#{System.unique_integer([:positive])}"

      case Node.start(name, :shortnames) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end

    :ok
  end

  def start_peer!(opts \\ []) do
    table_name = Keyword.fetch!(opts, :table_name)

    cookie = Node.get_cookie()

    {:ok, peer, peer_node} =
      :peer.start_link(%{
        name: :"live_stash_peer_#{System.unique_integer([:positive])}",
        args: [~c"-setcookie", to_charlist(cookie)]
      })

    # Ensure the peer can load this project's modules
    :ok = :erpc.call(peer_node, :code, :add_paths, [:code.get_path()])

    ensure_peer_ets_table!(peer_node, table_name)

    {peer, peer_node}
  end

  def ensure_peer_ets_table!(peer_node, table_name) do
    init_pid = :erpc.call(peer_node, :erlang, :whereis, [:init])

    _ =
      :erpc.call(peer_node, :ets, :new, [
        table_name,
        [
          :set,
          :public,
          :named_table,
          {:keypos, 2},
          {:write_concurrency, true},
          {:decentralized_counters, true},
          {:heir, init_pid, :live_stash}
        ]
      ])

    wait_for_peer_ets_table!(peer_node, table_name)
  end

  def put_state_on_peer!(peer_node, opts) do
    table_name = Keyword.fetch!(opts, :table_name)
    id = Keyword.fetch!(opts, :id)
    state = Keyword.fetch!(opts, :state)
    ttl = Keyword.get(opts, :ttl, 60_000)

    record = :erpc.call(peer_node, State, :new, [id, state, [ttl: ttl]])
    true = :erpc.call(peer_node, :ets, :insert, [table_name, record])
    :ok
  end

  def peer_has_state?(peer_node, id) do
    :erpc.call(peer_node, State, :get_by_id!, [id]) != :not_found
  end

  defp wait_for_peer_ets_table!(peer_node, table_name, attempts_left \\ 40) do
    case :erpc.call(peer_node, :ets, :whereis, [table_name]) do
      :undefined when attempts_left > 0 ->
        Process.sleep(50)
        wait_for_peer_ets_table!(peer_node, table_name, attempts_left - 1)

      :undefined ->
        raise "Timed out waiting for ETS table #{inspect(table_name)} on #{inspect(peer_node)}"

      _tid ->
        :ok
    end
  end
end
