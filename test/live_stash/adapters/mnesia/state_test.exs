defmodule LiveStash.Adapters.Mnesia.StateTest do
  use ExUnit.Case, async: false

  alias LiveStash.Adapters.Mnesia.Database.State

  setup do
    State.create_table!()

    for id <- [
          "test_id",
          "new_id",
          "existing_id",
          "get_id",
          "non_existent_id",
          "delete_id",
          "pop_id_exists",
          "pop_id_missing",
          "bump_id",
          "expired_1",
          "expired_2"
        ] do
      State.delete_by_id!(id)
    end

    :ok
  end

  describe "new/3" do
    test "creates a new state record with correct fields" do
      id = "test_id"
      state_map = %{key1: "value1", key2: "value2"}

      record = State.new(id, state_map, ttl: 1)

      assert record.id == id
      assert record.pid == self()
      assert record.ttl == 1
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
    test "updates delete_at time for existing record" do
      id = "bump_id"
      assert :ok = State.put!(id, %{key: "value"}, ttl: 1)

      assert {:ok, _state} = State.get_by_id!(id)
      assert State.bump_delete_at!(id, System.os_time(:second) + 10) == :ok
    end

    test "returns :ok even when record does not exist" do
      assert State.bump_delete_at!("non_existent_id", 1_234_567_890) == :ok
    end
  end

  describe "expired_records/1" do
    test "returns expired records" do
      now = System.os_time(:second)
      past_time = now - 5

      assert :ok = State.put!("expired_1", %{key: "value1"}, ttl: 1)
      assert :ok = State.put!("expired_2", %{key: "value2"}, ttl: 1)

      assert State.bump_delete_at!("expired_1", past_time) == :ok
      assert State.bump_delete_at!("expired_2", past_time) == :ok

      ids = State.expired_records(now) |> Enum.map(fn {id, _pid, _ttl} -> id end)

      assert "expired_1" in ids
      assert "expired_2" in ids
    end

    test "returns an empty list when no expired records exist" do
      assert Enum.to_list(State.expired_records(System.os_time(:second))) == []
    end
  end
end
