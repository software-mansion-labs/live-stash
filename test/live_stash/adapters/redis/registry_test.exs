defmodule LiveStash.Adapters.Redis.RegistryTest do
  use ExUnit.Case, async: false

  require LiveStash.Adapters.Redis.Registry

  alias LiveStash.Adapters.Redis.Registry

  @table_name Application.compile_env(:live_stash, :ets_table_name, :live_stash_redis_registry)

  setup do
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete(@table_name)
    end

    Registry.create_table!()

    :ok
  end

  describe "new/2" do
    test "creates a new registry record with correct fields" do
      id = "test_id"
      ttl = 1000

      record = Registry.new(id, ttl: ttl)

      assert {:registry, ^id, pid, delete_at, ^ttl} = record
      assert pid == self()
      assert is_integer(delete_at)
    end

    test "raises when ttl is missing from opts" do
      assert_raise KeyError, fn ->
        Registry.new("test_id", [])
      end
    end
  end

  describe "insert!/1" do
    test "inserts a record into the ETS table" do
      record = Registry.new("test_id", ttl: 1000)
      assert Registry.insert!(record) == :ok

      assert [{:registry, "test_id", _pid, _delete_at, _ttl}] =
               :ets.lookup(@table_name, "test_id")
    end
  end

  describe "put!/2" do
    test "creates a new registry record when id doesn't exist" do
      id = "new_id"
      assert Registry.put!(id, ttl: 1000) == :ok

      assert {:ok, _pid, _delete_at, 1000} = Registry.get_by_id!(id)
    end

    test "replaces existing registry data when id exists and is owned by the current process" do
      id = "existing_id"

      assert :ok = Registry.put!(id, ttl: 1000)
      assert :ok = Registry.put!(id, ttl: 2000)

      assert {:ok, pid, _delete_at, ttl} = Registry.get_by_id!(id)
      assert pid == self()
      assert ttl == 2000
    end

    test "raises exception if registry is owned by a different process (PID mismatch)" do
      id = "test_id"
      opts = [ttl: 1000]

      Task.async(fn ->
        Registry.put!(id, opts)
      end)
      |> Task.await()

      assert_raise RuntimeError, fn ->
        Registry.put!(id, opts)
      end
    end
  end

  describe "get_by_id!/1" do
    test "returns {:ok, pid, delete_at, ttl} when record exists" do
      id = "get_id"
      ttl = 1000
      record = Registry.new(id, ttl: ttl)
      Registry.insert!(record)

      assert {:ok, pid, _delete_at, current_ttl} = Registry.get_by_id!(id)
      assert pid == self()
      assert current_ttl == ttl
    end

    test "returns :not_found when record doesn't exist" do
      assert :not_found == Registry.get_by_id!("non_existent_id")
    end
  end

  describe "delete_by_id!/1" do
    test "deletes an existing record" do
      id = "delete_id"
      record = Registry.new(id, ttl: 1000)
      Registry.insert!(record)

      assert Registry.delete_by_id!(id) == :ok
      assert :not_found == Registry.get_by_id!(id)
    end

    test "returns :ok even when record doesn't exist" do
      assert Registry.delete_by_id!("non_existent_id") == :ok
    end
  end

  describe "bump_delete_at!/2" do
    test "updates delete_at time for existing record" do
      id = "bump_id"
      record = Registry.new(id, ttl: 1000)
      Registry.insert!(record)

      [{:registry, ^id, _pid, original_delete_at, _ttl}] = :ets.lookup(@table_name, id)
      new_time = original_delete_at + 5000

      assert Registry.bump_delete_at!(id, new_time) == :ok

      [{:registry, ^id, _pid, delete_at, _ttl}] = :ets.lookup(@table_name, id)
      assert delete_at == new_time
    end

    test "returns :ok even when record doesn't exist" do
      assert Registry.bump_delete_at!("non_existent_id", 1_234_567_890) == :ok
    end
  end

  describe "get_batch!/1" do
    test "returns expired records" do
      now = System.os_time(:millisecond)
      past_time = now - 5000

      expired_id1 = "expired_1"
      expired_id2 = "expired_2"

      expired_record1 =
        Registry.registry(
          id: expired_id1,
          pid: self(),
          delete_at: past_time,
          ttl: 1000
        )

      expired_record2 =
        Registry.registry(
          id: expired_id2,
          pid: self(),
          delete_at: past_time,
          ttl: 1000
        )

      Registry.insert!(expired_record1)
      Registry.insert!(expired_record2)

      future_id = "future_id"
      future_record = Registry.new(future_id, ttl: 1000)
      Registry.insert!(future_record)

      assert {candidates, _continuation} = Registry.get_batch!(now)

      ids = Enum.map(candidates, fn {id, _pid, _ttl} -> id end)
      assert expired_id1 in ids
      assert expired_id2 in ids
      refute future_id in ids
    end

    test "returns :$end_of_table when no expired records exist" do
      now = System.os_time(:millisecond)
      future_time = now + 5000

      future_record = Registry.new("future_id", ttl: 1000)
      future_record = put_elem(future_record, 3, future_time)
      Registry.insert!(future_record)

      assert :"$end_of_table" == Registry.get_batch!(now)
    end
  end

  describe "get_next_batch!/1" do
    test "returns next batch from continuation" do
      now = System.os_time(:millisecond)
      past_time = now - 5000

      records =
        for i <- 1..150 do
          Registry.registry(
            id: "batch_#{i}",
            pid: self(),
            delete_at: past_time,
            ttl: 1000
          )
        end

      Enum.each(records, &Registry.insert!/1)

      assert {first_candidates, continuation} = Registry.get_batch!(now)
      assert length(first_candidates) == 100
      assert is_tuple(continuation)

      assert {next_candidates, _next_continuation} = Registry.get_next_batch!(continuation)
      assert length(next_candidates) == 50
    end

    test "returns :$end_of_table when continuation is :$end_of_table" do
      assert Registry.get_next_batch!(:"$end_of_table") == :"$end_of_table"
    end
  end
end
