defmodule LiveStash.Server.CleanerTest do
  use ExUnit.Case, async: false

  require LiveStash.Adapters.ETS.State

  alias LiveStash.Adapters.ETS.Cleaner
  alias LiveStash.Adapters.ETS.State

  @table_name Application.compile_env(:live_stash, :ets_table_name, :live_stash_server_storage)

  setup do
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete(@table_name)
    end

    State.create_table!()

    :ok
  end

  describe "clean_expired_states!/0" do
    test "does not clear records that are not expired" do
      now = System.os_time(:second)
      future_time = now + 5

      future_record =
        State.state(
          id: "future_id",
          pid: self(),
          delete_at: future_time,
          ttl: 1,
          state: %{key: "value"}
        )

      State.insert!(future_record)

      assert Cleaner.clean_expired_states!() == :ok
      assert length(:ets.tab2list(@table_name)) == 1
    end

    test "bumps delete_at time for records with alive processes" do
      now = System.os_time(:second)
      past_time = now - 5
      ttl = 1

      expired_record =
        State.state(
          id: "alive_expired",
          pid: self(),
          delete_at: past_time,
          ttl: ttl,
          state: %{key: "value"}
        )

      State.insert!(expired_record)

      Cleaner.clean_expired_states!()

      assert [{:state, "alive_expired", _pid, delete_at, _ttl, _state}] =
               :ets.lookup(@table_name, "alive_expired")

      assert delete_at >= now + ttl
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

      expired_record =
        State.state(
          id: "dead_expired",
          pid: dead_pid,
          delete_at: past_time,
          ttl: 1,
          state: %{key: "value"}
        )

      State.insert!(expired_record)

      Process.exit(dead_pid, :kill)
      Process.sleep(100)

      assert Cleaner.clean_expired_states!() == :ok
      assert :ets.tab2list(@table_name) == []
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

      alive_record =
        State.state(
          id: "alive_mixed",
          pid: self(),
          delete_at: past_time,
          ttl: ttl,
          state: %{key: "alive"}
        )

      dead_record =
        State.state(
          id: "dead_mixed",
          pid: dead_pid,
          delete_at: past_time,
          ttl: ttl,
          state: %{key: "dead"}
        )

      State.insert!(alive_record)
      State.insert!(dead_record)

      Process.exit(dead_pid, :kill)
      Process.sleep(100)

      Cleaner.clean_expired_states!()

      assert length(:ets.tab2list(@table_name)) == 1

      assert [{:state, "alive_mixed", _pid, delete_at, _ttl, _state}] =
               :ets.lookup(@table_name, "alive_mixed")

      assert delete_at >= now + ttl
    end

    test "handles continuation batches" do
      now = System.os_time(:second)
      past_time = now - 5
      ttl = 1

      records =
        for i <- 1..150 do
          State.state(
            id: "batch_#{i}",
            pid: self(),
            delete_at: past_time,
            ttl: ttl,
            state: %{key: "value"}
          )
        end

      dead_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      Process.exit(dead_pid, :kill)
      Process.sleep(100)

      dead_record =
        State.state(
          id: "dead_mixed",
          pid: dead_pid,
          delete_at: past_time,
          ttl: ttl,
          state: %{key: "dead"}
        )

      Enum.each(records, &State.insert!/1)
      State.insert!(dead_record)
      assert length(:ets.tab2list(@table_name)) == 151

      Cleaner.clean_expired_states!()

      assert length(:ets.tab2list(@table_name)) == 150

      for i <- 1..150 do
        id = "batch_#{i}"
        [{:state, ^id, _pid, delete_at, _ttl, _state}] = :ets.lookup(@table_name, id)

        assert delete_at >= now + ttl
      end
    end
  end
end
