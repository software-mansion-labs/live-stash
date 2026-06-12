defmodule LiveStash.Adapters.Mnesia.MnesiaCleanerTest do
  use ExUnit.Case, async: false

  alias LiveStash.Adapters.Mnesia.Cleaner
  alias LiveStash.Adapters.Mnesia.State

  setup_all do
    State.ensure_cluster_table!()
    :ok
  end

  setup do
    Memento.Table.clear(LiveStash.Adapters.Mnesia.State)

    :ok
  end

  defp force_delete_at(id, delete_at) do
    Memento.transaction!(fn ->
      record = Memento.Query.read(LiveStash.Adapters.Mnesia.State, id)
      Memento.Query.write(%{record | delete_at: delete_at})
    end)
  end

  describe "clean_expired_states!/0" do
    test "does not clear records that are not expired" do
      assert :ok = State.put!("future_id", %{key: "value"}, ttl: 86_400)

      assert Cleaner.clean_expired_states!() == :ok
      assert {:ok, _} = State.get_by_id!("future_id")
    end

    test "deletes expired records regardless of whether the owning process is alive" do
      assert :ok = State.put!("alive_expired", %{key: "alive"}, ttl: 1)
      assert :ok = State.put!("dead_expired", %{key: "dead"}, ttl: 1)

      past = System.os_time(:second) - 5
      force_delete_at("alive_expired", past)
      force_delete_at("dead_expired", past)

      assert Cleaner.clean_expired_states!() == :ok

      assert :not_found == State.get_by_id!("alive_expired")
      assert :not_found == State.get_by_id!("dead_expired")
    end

    test "leaves non-expired records intact when mixed with expired ones" do
      assert :ok = State.put!("expired", %{key: "expired"}, ttl: 1)
      assert :ok = State.put!("fresh", %{key: "fresh"}, ttl: 86_400)

      force_delete_at("expired", System.os_time(:second) - 5)

      assert Cleaner.clean_expired_states!() == :ok

      assert :not_found == State.get_by_id!("expired")
      assert {:ok, %{key: "fresh"}} = State.get_by_id!("fresh")
    end
  end
end
