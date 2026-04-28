defmodule LiveStash.Server.MnesiaCleanerTest do
  use ExUnit.Case, async: false

  alias LiveStash.Adapters.Mnesia.Cleaner
  alias LiveStash.Adapters.Mnesia.State

  setup_all do
    State.setup_cluster_state!()
    on_exit(fn -> Memento.stop() end)
    :ok
  end

  setup do
    Memento.Table.clear(LiveStash.Adapters.Mnesia.State)

    :ok
  end

  describe "clean_expired_states!/0" do
    test "does not clear records that are not expired" do
      now = System.os_time(:second)
      future_time = now + 5

      future_record = State.new("future_id", %{key: "value"}, ttl: 1)

      State.insert!(%{future_record | delete_at: future_time})

      assert Cleaner.clean_expired_states!() == :ok
      assert {:ok, _} = State.get_by_id!("future_id")
    end

    test "bumps delete_at time for records with alive processes" do
      now = System.os_time(:second)
      past_time = now - 5
      ttl = 1

      record = State.new("alive_expired", %{key: "value"}, ttl: ttl)
      State.insert!(%{record | delete_at: past_time})

      Cleaner.clean_expired_states!()

      # after cleaning the previously-expired but alive record should no longer be expired
      expired_ids = State.expired_records(now) |> Enum.map(fn {id, _pid, _ttl} -> id end)
      refute "alive_expired" in expired_ids
    end

    test "deletes expired records with dead processes" do
      now = System.os_time(:second)
      past_time = now - 5

      dead_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      record = State.new("dead_expired", %{key: "value"}, ttl: 1)
      State.insert!(%{record | pid: dead_pid, delete_at: past_time})

      Process.exit(dead_pid, :kill)
      Process.sleep(100)

      assert Cleaner.clean_expired_states!() == :ok
      assert :not_found == State.get_by_id!("dead_expired")
    end

    test "handles mixed alive and dead processes" do
      now = System.os_time(:second)
      past_time = now - 5
      ttl = 1

      dead_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      alive_record = State.new("alive_mixed", %{key: "alive"}, ttl: ttl)
      dead_record = State.new("dead_mixed", %{key: "dead"}, ttl: ttl)

      State.insert!(%{alive_record | delete_at: past_time})
      State.insert!(%{dead_record | pid: dead_pid, delete_at: past_time})

      Process.exit(dead_pid, :kill)
      Process.sleep(100)

      Cleaner.clean_expired_states!()

      assert {:ok, _} = State.get_by_id!("alive_mixed")

      assert :not_found == State.get_by_id!("dead_mixed")
    end

    test "handles continuation batches" do
      now = System.os_time(:second)
      past_time = now - 5
      ttl = 1

      records =
        for i <- 1..150 do
          State.new("batch_#{i}", %{key: "value"}, ttl: ttl)
        end

      dead_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      Process.exit(dead_pid, :kill)
      Process.sleep(100)

      dead_record = State.new("dead_mixed", %{key: "dead"}, ttl: ttl)

      Enum.each(records, fn r -> State.insert!(%{r | delete_at: past_time}) end)
      State.insert!(%{dead_record | pid: dead_pid, delete_at: past_time})

      for i <- 1..150 do
        assert {:ok, _} = State.get_by_id!("batch_#{i}")
      end

      Cleaner.clean_expired_states!()

      assert :not_found == State.get_by_id!("dead_mixed")

      for i <- 1..150 do
        assert {:ok, _} = State.get_by_id!("batch_#{i}")
      end
    end
  end
end
