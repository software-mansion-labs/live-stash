defmodule LiveStash.Adapters.Mnesia.StateTest do
  use ExUnit.Case, async: false

  alias LiveStash.Adapters.Mnesia.State

  setup_all do
    State.ensure_cluster_table!()
    :ok
  end

  setup do
    Memento.Table.clear(LiveStash.Adapters.Mnesia.State)

    :ok
  end

  describe "new/3" do
    test "creates a new state record with correct fields" do
      id = "test_id"
      state_map = %{key1: "value1", key2: "value2"}

      record = State.new(id, state_map, ttl: 1)

      assert record.id == id
      assert record.pid == self()
      assert record.state == state_map
      assert is_integer(record.delete_at)
    end

    test "raises when ttl is missing from opts" do
      assert_raise KeyError, fn ->
        State.new("test_id", %{}, [])
      end
    end
  end

  describe "put!/3" do
    test "creates a new state record when id does not exist" do
      assert State.put!("new_id", %{key: "value"}, ttl: 1) == :ok
      assert {:ok, %{key: "value"}} = State.get_by_id!("new_id")
    end

    test "replaces existing state map when id exists and is owned by the current process" do
      id = "existing_id"

      assert :ok = State.put!(id, %{key1: "value1", key2: "value2"}, ttl: 1)
      assert :ok = State.put!(id, %{key2: "new_value"}, ttl: 2)

      assert {:ok, state} = State.get_by_id!(id)
      assert state == %{key2: "new_value"}
    end

    test "raises exception if state is owned by a different process" do
      id = "test_id"

      Task.async(fn ->
        State.put!(id, %{key: "old_value"}, ttl: 1)
      end)
      |> Task.await()

      assert_raise RuntimeError, fn ->
        State.put!(id, %{key: "new_value"}, ttl: 1)
      end
    end
  end

  describe "get_by_id!/1" do
    test "returns {:ok, state} when record exists" do
      id = "get_id"
      state_map = %{key: "value"}

      assert :ok = State.put!(id, state_map, ttl: 1)
      assert {:ok, ^state_map} = State.get_by_id!(id)
    end

    test "returns :not_found when record does not exist" do
      assert :not_found == State.get_by_id!("non_existent_id")
    end
  end

  describe "delete_by_id!/1" do
    test "deletes an existing record" do
      id = "delete_id"
      assert :ok = State.put!(id, %{key: "value"}, ttl: 1)

      assert State.delete_by_id!(id) == :ok
      assert :not_found == State.get_by_id!(id)
    end

    test "returns :ok even when record does not exist" do
      assert State.delete_by_id!("non_existent_id") == :ok
    end
  end

  describe "bump_delete_at!/2" do
    test "refreshes delete_at to now + ttl for an existing record" do
      id = "bump_id"
      assert :ok = State.put!(id, %{key: "value"}, ttl: 1)

      assert State.bump_delete_at!(id, 100) == :ok

      record =
        Memento.transaction!(fn -> Memento.Query.read(LiveStash.Adapters.Mnesia.State, id) end)

      now = System.os_time(:second)
      assert record.delete_at >= now + 99
      assert record.delete_at <= now + 100
    end

    test "returns :ok even when record does not exist" do
      assert State.bump_delete_at!("non_existent_id", 60) == :ok
    end
  end

  describe "delete_expired!/1 and /2" do
    test "deletes only records whose delete_at is strictly less than now" do
      assert :ok = State.put!("expired_1", %{key: "value1"}, ttl: 1)
      assert :ok = State.put!("expired_2", %{key: "value2"}, ttl: 1)
      assert :ok = State.put!("fresh", %{key: "fresh"}, ttl: 86_400)

      Memento.transaction!(fn ->
        for id <- ["expired_1", "expired_2"] do
          record = Memento.Query.read(LiveStash.Adapters.Mnesia.State, id)
          Memento.Query.write(%{record | delete_at: System.os_time(:second) - 5})
        end
      end)

      # Relies on the default batch_size (which is larger than 2)
      assert State.delete_expired!(System.os_time(:second)) == 2

      assert :not_found == State.get_by_id!("expired_1")
      assert :not_found == State.get_by_id!("expired_2")
      assert {:ok, _} = State.get_by_id!("fresh")
    end

    test "returns 0 when nothing is expired" do
      assert :ok = State.put!("fresh", %{key: "fresh"}, ttl: 86_400)

      assert State.delete_expired!(System.os_time(:second)) == 0
      assert {:ok, _} = State.get_by_id!("fresh")
    end

    test "deletes records in batches when expired records exceed batch_size" do
      for i <- 1..5 do
        assert :ok = State.put!("batch_expired_#{i}", %{key: "val"}, ttl: 1)
      end

      # 2. Create 2 fresh records
      for i <- 1..2 do
        assert :ok = State.put!("batch_fresh_#{i}", %{key: "val"}, ttl: 86_400)
      end

      # 3. Manually push the delete_at into the past for the 5 expired records
      Memento.transaction!(fn ->
        for i <- 1..5 do
          record = Memento.Query.read(LiveStash.Adapters.Mnesia.State, "batch_expired_#{i}")
          Memento.Query.write(%{record | delete_at: System.os_time(:second) - 5})
        end
      end)

      assert State.delete_expired!(System.os_time(:second), 2) == 5

      for i <- 1..5 do
        assert :not_found == State.get_by_id!("batch_expired_#{i}")
      end

      for i <- 1..2 do
        assert {:ok, _} = State.get_by_id!("batch_fresh_#{i}")
      end
    end
  end
end
