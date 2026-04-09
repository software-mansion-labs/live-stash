defmodule LiveStash.Adapters.ETS.StateFinderTest do
  use ExUnit.Case, async: false

  alias LiveStash.Adapters.ETS.State
  alias LiveStash.Adapters.ETS.StateFinder
  alias LiveStash.TestSupport.ClusterHelpers

  @table_name Application.compile_env(:live_stash, :ets_table_name, :live_stash_server_storage)

  setup_all do
    ClusterHelpers.ensure_distribution_started!()
    :ok
  end

  setup do
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete(@table_name)
    end

    State.create_table!()

    {:ok, id: "test_state_id"}
  end

  describe "get_from_cluster/2" do
    test "scenario 1: returns state from local ETS (no remote calls)", %{id: id} do
      {peer1, peer1_node} = ClusterHelpers.start_peer!(table_name: @table_name)
      {peer2, peer2_node} = ClusterHelpers.start_peer!(table_name: @table_name)

      try do
        true = Node.connect(peer1_node)
        true = Node.connect(peer2_node)

        local_state = %{from: :local}
        :ok = State.insert!(State.new(id, local_state, ttl: 60_000))

        # Put state on peers too; it should NOT be popped if local state is found.
        :ok =
          ClusterHelpers.put_state_on_peer!(peer1_node,
            table_name: @table_name,
            id: id,
            state: %{from: peer1_node}
          )

        :ok =
          ClusterHelpers.put_state_on_peer!(peer2_node,
            table_name: @table_name,
            id: id,
            state: %{from: peer2_node}
          )

        assert {:ok, ^local_state} = StateFinder.get_from_cluster(id, peer1_node)

        # We check that the state is still on the peer nodes because we didn't call them.
        assert ClusterHelpers.peer_has_state?(peer1_node, id)
        assert ClusterHelpers.peer_has_state?(peer2_node, id)
      after
        :peer.stop(peer1)
        :peer.stop(peer2)
      end
    end

    test "scenario 2: state is on another node and we have node_hint (only hinted node called)",
         %{id: id} do
      {peer1, peer1_node} = ClusterHelpers.start_peer!(table_name: @table_name)
      {peer2, peer2_node} = ClusterHelpers.start_peer!(table_name: @table_name)

      try do
        true = Node.connect(peer1_node)
        true = Node.connect(peer2_node)

        # Put the same id on both peers.
        # If StateFinder incorrectly multicalls other nodes even when node_hint succeeds,
        # it would pop the state on peer2 as well.
        peer1_state = %{from: peer1_node}
        peer2_state = %{from: peer2_node}

        :ok =
          ClusterHelpers.put_state_on_peer!(peer1_node,
            table_name: @table_name,
            id: id,
            state: peer1_state
          )

        :ok =
          ClusterHelpers.put_state_on_peer!(peer2_node,
            table_name: @table_name,
            id: id,
            state: peer2_state
          )

        assert {:ok, ^peer1_state} = StateFinder.get_from_cluster(id, peer1_node)

        refute ClusterHelpers.peer_has_state?(peer1_node, id)
        assert ClusterHelpers.peer_has_state?(peer2_node, id)
      after
        :peer.stop(peer1)
        :peer.stop(peer2)
      end
    end

    test "scenario 3: state is on another node and we don't have hint (all nodes called)", %{
      id: id
    } do
      {peer1, peer1_node} = ClusterHelpers.start_peer!(table_name: @table_name)
      {peer2, peer2_node} = ClusterHelpers.start_peer!(table_name: @table_name)

      try do
        true = Node.connect(peer1_node)
        true = Node.connect(peer2_node)

        peer1_state = %{from: peer1_node}
        peer2_state = %{from: peer2_node}

        :ok =
          ClusterHelpers.put_state_on_peer!(peer1_node,
            table_name: @table_name,
            id: id,
            state: peer1_state
          )

        :ok =
          ClusterHelpers.put_state_on_peer!(peer2_node,
            table_name: @table_name,
            id: id,
            state: peer2_state
          )

        assert {:ok, recovered_state} = StateFinder.get_from_cluster(id, nil)
        assert recovered_state in [peer1_state, peer2_state]

        # multicall uses pop; all nodes should have been popped regardless of which returned first
        refute ClusterHelpers.peer_has_state?(peer1_node, id)
        refute ClusterHelpers.peer_has_state?(peer2_node, id)
      after
        :peer.stop(peer1)
        :peer.stop(peer2)
      end
    end

    test "scenario 4: node_hint misses, then falls back to all other nodes", %{id: id} do
      {peer1, peer1_node} = ClusterHelpers.start_peer!(table_name: @table_name)
      {peer_hint, peer_hint_node} = ClusterHelpers.start_peer!(table_name: @table_name)
      {peer3, peer3_node} = ClusterHelpers.start_peer!(table_name: @table_name)

      try do
        true = Node.connect(peer1_node)
        true = Node.connect(peer_hint_node)
        true = Node.connect(peer3_node)

        peer1_state = %{from: peer1_node}
        peer3_state = %{from: peer3_node}

        # Ensure the hint node does NOT have the state.
        # Put the same id on the other nodes so we can verify they were contacted (pop'ed).
        :ok =
          ClusterHelpers.put_state_on_peer!(peer1_node,
            table_name: @table_name,
            id: id,
            state: peer1_state
          )

        :ok =
          ClusterHelpers.put_state_on_peer!(peer3_node,
            table_name: @table_name,
            id: id,
            state: peer3_state
          )

        assert {:ok, recovered_state} = StateFinder.get_from_cluster(id, peer_hint_node)
        assert recovered_state in [peer1_state, peer3_state]

        # Since node_hint missed, we should have fallen back to asking every other node.
        refute ClusterHelpers.peer_has_state?(peer1_node, id)
        refute ClusterHelpers.peer_has_state?(peer3_node, id)
      after
        :peer.stop(peer1)
        :peer.stop(peer_hint)
        :peer.stop(peer3)
      end
    end
  end
end
