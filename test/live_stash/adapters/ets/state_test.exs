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

      assert {:state, ^id, pid, delete_at, ttl, ^state_map} = record
      assert pid == self()
      assert ttl == 1
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

      assert [{:state, "test_id", _pid, _delete_at, _ttl, %{key: "value"}}] =
               :ets.lookup(@table_name, "test_id")
    end
  end

  describe "put!/4" do
    test "creates a new state record when id doesn't exist" do
      id = "new_id"
      assert State.put!(id, %{key: "value"}, ttl: 1) == :ok

      assert {:ok, %{key: "value"}} = State.get_by_id!(id)
    end

    test "updates existing state record when id exists" do
      id = "existing_id"
      opts = [ttl: 1]
      State.put!(id, %{key1: "value1"}, opts)
      State.put!(id, %{key2: "value2"}, opts)

      assert {:ok, state} = State.get_by_id!(id)
      assert state.key1 == "value1"
      assert state.key2 == "value2"
    end

    test "overwrites existing key when updating" do
      id = "update_id"
      opts = [ttl: 1]
      State.put!(id, %{key: "value1"}, opts)
      State.put!(id, %{key: "value2"}, opts)

      assert {:ok, %{key: "value2"}} = State.get_by_id!(id)
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
    test "updates delete_at time for existing record" do
      id = "bump_id"
      record = State.new(id, %{key: "value"}, ttl: 1)
      State.insert!(record)

      [{:state, ^id, _pid, original_delete_at, _ttl, _state}] = :ets.lookup(@table_name, id)
      new_time = original_delete_at + 5

      assert State.bump_delete_at!(id, new_time) == :ok

      [{:state, ^id, _pid, delete_at, _ttl, _state}] = :ets.lookup(@table_name, id)
      assert delete_at == new_time
    end

    test "returns :ok even when record doesn't exist" do
      assert State.bump_delete_at!("non_existent_id", 1_234_567_890) == :ok
    end
  end

  describe "get_batch!/1" do
    test "returns expired records" do
      now = System.os_time(:second)
      past_time = now - 5

      expired_id1 = "expired_1"
      expired_id2 = "expired_2"

      expired_record1 =
        State.state(
          id: expired_id1,
          pid: self(),
          delete_at: past_time,
          ttl: 1,
          state: %{key: "value1"}
        )

      expired_record2 =
        State.state(
          id: expired_id2,
          pid: self(),
          delete_at: past_time,
          ttl: 1,
          state: %{key: "value2"}
        )

      State.insert!(expired_record1)
      State.insert!(expired_record2)

      future_id = "future_id"
      future_record = State.new("future_id", %{key: "value"}, ttl: 1)
      State.insert!(future_record)

      assert {candidates, _continuation} = State.get_batch!(now)

      ids = Enum.map(candidates, fn {id, _pid, _ttl} -> id end)
      assert expired_id1 in ids
      assert expired_id2 in ids
      refute future_id in ids
    end

    test "returns :$end_of_table when no expired records exist" do
      now = System.os_time(:second)
      future_time = now + 5

      future_record = State.new("future_id", %{key: "value"}, ttl: 1)
      future_record = put_elem(future_record, 3, future_time)
      State.insert!(future_record)

      assert :"$end_of_table" == State.get_batch!(now)
    end
  end

  describe "get_next_batch!/1" do
    test "returns next batch from continuation" do
      now = System.os_time(:second)
      past_time = now - 5

      records =
        for i <- 1..150 do
          State.state(
            id: "batch_#{i}",
            pid: self(),
            delete_at: past_time,
            ttl: 1,
            state: %{key: "value"}
          )
        end

      Enum.each(records, &State.insert!/1)

      assert {first_candidates, continuation} = State.get_batch!(now)
      assert length(first_candidates) == 100
      assert is_tuple(continuation)

      assert {next_candidates, _next_continuation} = State.get_next_batch!(continuation)
      assert length(next_candidates) == 50
    end

    test "returns :$end_of_table when continuation is :$end_of_table" do
      assert State.get_next_batch!(:"$end_of_table") == :"$end_of_table"
    end
  end
end
