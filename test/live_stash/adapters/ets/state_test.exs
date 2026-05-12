defmodule LiveStash.Adapters.ETS.StateTest do
  use ExUnit.Case, async: false

  require LiveStash.Adapters.ETS.State
  alias LiveStash.Adapters.ETS.State

  @table_name Application.compile_env(:live_stash, :ets_table_name, :live_stash_server_storage)

  setup do
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete(@table_name)
    end

    State.create_table!()

    :ok
  end

  describe "new/3" do
    test "creates a new state record with correct fields" do
      id = "test_id"
      state_map = %{key1: "value1", key2: "value2"}
      opts = [ttl: 1]

      record = State.new(id, state_map, opts)

      assert {:state, ^id, pid, delete_at, ^state_map} = record
      assert pid == self()
      assert is_integer(delete_at)
    end

    test "raises when ttl is missing from opts" do
      assert_raise KeyError, fn ->
        State.new("test_id", %{}, [])
      end
    end
  end

  describe "insert!/1" do
    test "inserts a record into the ETS table" do
      record = State.new("test_id", %{key: "value"}, ttl: 1)
      assert State.insert!(record) == :ok

      assert [{:state, "test_id", _pid, _delete_at, %{key: "value"}}] =
               :ets.lookup(@table_name, "test_id")
    end
  end

  describe "put!/3" do
    test "creates a new state record when id doesn't exist" do
      id = "new_id"
      assert State.put!(id, %{key: "value"}, ttl: 1) == :ok

      assert {:ok, %{key: "value"}} = State.get_by_id!(id)
    end

    test "replaces existing state map when id exists and is owned by the current process" do
      id = "existing_id"

      assert :ok = State.put!(id, %{key1: "value1", key2: "value2"}, ttl: 1)

      assert :ok = State.put!(id, %{key2: "new_value"}, ttl: 2)

      assert {:ok, state} = State.get_by_id!(id)
      assert state == %{key2: "new_value"}
    end

    test "raises exception if state is owned by a different process (PID mismatch)" do
      id = "test_id"
      opts = [ttl: 1]

      Task.async(fn ->
        State.put!(id, %{key: "old_value"}, opts)
      end)
      |> Task.await()

      assert_raise RuntimeError, fn ->
        State.put!(id, %{key: "new_value"}, opts)
      end
    end
  end

  describe "get_by_id!/1" do
    test "returns {:ok, state} when record exists" do
      id = "get_id"
      state_map = %{key: "value"}
      record = State.new(id, state_map, ttl: 1)
      State.insert!(record)

      assert {:ok, state_map} == State.get_by_id!(id)
    end

    test "returns :not_found when record doesn't exist" do
      assert :not_found == State.get_by_id!("non_existent_id")
    end
  end

  describe "delete_by_id!/1" do
    test "deletes an existing record" do
      id = "delete_id"
      record = State.new(id, %{key: "value"}, ttl: 1)
      State.insert!(record)

      assert State.delete_by_id!(id) == :ok
      assert :not_found == State.get_by_id!(id)
    end

    test "returns :ok even when record doesn't exist" do
      assert State.delete_by_id!("non_existent_id") == :ok
    end
  end

  describe "pop_by_id!/1" do
    test "returns {:ok, state} and deletes the record when it exists" do
      id = "pop_id_exists"
      state_map = %{key: "value"}
      opts = [ttl: 5]

      record = State.new(id, state_map, opts)
      State.insert!(record)

      assert {:ok, ^state_map} = State.get_by_id!(id)

      assert {:ok, popped_state} = State.pop_by_id!(id)

      assert popped_state == state_map

      assert :not_found == State.get_by_id!(id)
    end

    test "returns :not_found when the record does not exist" do
      id = "pop_id_missing"

      assert :not_found == State.get_by_id!(id)

      assert :not_found == State.pop_by_id!(id)
    end
  end

  describe "bump_delete_at!/2" do
    test "refreshes delete_at to now + ttl for an existing record" do
      id = "bump_id"
      record = State.new(id, %{key: "value"}, ttl: 1)
      State.insert!(record)

      [{:state, ^id, _pid, _original_delete_at, _state}] = :ets.lookup(@table_name, id)

      assert State.bump_delete_at!(id, 100) == :ok

      now = System.os_time(:second)
      [{:state, ^id, _pid, delete_at, _state}] = :ets.lookup(@table_name, id)
      assert delete_at >= now + 99
      assert delete_at <= now + 100
    end

    test "returns :ok even when record doesn't exist" do
      assert State.bump_delete_at!("non_existent_id", 60) == :ok
    end
  end

  describe "delete_expired!/1" do
    test "deletes only records whose delete_at is strictly less than now" do
      now = System.os_time(:second)
      past_time = now - 5

      expired_record1 =
        State.state(
          id: "expired_1",
          pid: self(),
          delete_at: past_time,
          state: %{key: "value1"}
        )

      expired_record2 =
        State.state(
          id: "expired_2",
          pid: self(),
          delete_at: past_time,
          state: %{key: "value2"}
        )

      future_record = State.new("future_id", %{key: "value"}, ttl: 60)

      State.insert!(expired_record1)
      State.insert!(expired_record2)
      State.insert!(future_record)

      assert State.delete_expired!(now) == 2

      assert :not_found == State.get_by_id!("expired_1")
      assert :not_found == State.get_by_id!("expired_2")
      assert {:ok, _} = State.get_by_id!("future_id")
    end

    test "returns 0 when no records are expired" do
      future_record = State.new("future_id", %{key: "value"}, ttl: 60)
      State.insert!(future_record)

      assert State.delete_expired!(System.os_time(:second)) == 0
      assert {:ok, _} = State.get_by_id!("future_id")
    end
  end
end
