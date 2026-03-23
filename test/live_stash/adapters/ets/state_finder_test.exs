defmodule LiveStash.Adapters.ETS.StateFinderTest do
  use ExUnit.Case, async: false

  require LiveStash.Adapters.ETS.State

  alias LiveStash.Adapters.ETS.State
  alias LiveStash.Adapters.ETS.StateFinder

  @table_name Application.compile_env(:live_stash, :ets_table_name, :live_stash_server_storage)

  setup do
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete(@table_name)
    end

    State.create_table!()

    {:ok, id: "test_state_id"}
  end

  describe "get_from_cluster/2" do
    test "returns state from local ETS if present", %{id: id} do
      state_data = %{user: "user"}

      State.insert!(
        State.state(
          id: id,
          pid: self(),
          delete_at: System.os_time(:millisecond) + 60_000,
          ttl: 100,
          state: state_data
        )
      )

      assert {:ok, ^state_data} = StateFinder.get_from_cluster(id, :fake_node@localhost)
    end

    test "returns :not_found if not in local ETS and no node_hint is provided (empty cluster)", %{
      id: id
    } do
      assert :not_found = StateFinder.get_from_cluster(id, nil)
    end

    test "returns :not_found if node_hint is self() and not in local ETS", %{id: id} do
      assert :not_found = StateFinder.get_from_cluster(id, Node.self())
    end
  end
end
