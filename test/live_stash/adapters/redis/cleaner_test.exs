defmodule LiveStash.Adapters.Redis.CleanerTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  require LiveStash.Adapters.Redis.Registry

  alias LiveStash.Adapters.Redis.Cleaner
  alias LiveStash.Adapters.Redis.Registry
  alias LiveStash.Adapters.Redis

  @table_name Application.compile_env(:live_stash, :ets_table_name, :live_stash_redis_registry)

  setup do
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete(@table_name)
    end

    Registry.create_table!()
    LiveStash.TestRedisConn.stop()
    {:ok, _pid} = LiveStash.TestRedisConn.start_link(name: LiveStash.Adapters.Redis.Conn)

    on_exit(fn -> LiveStash.TestRedisConn.stop() end)

    :ok
  end

  describe "clean_expired_states!/0" do
    test "does not clear records that are not expired" do
      now = System.os_time(:millisecond)
      future_time = now + 5000

      future_record =
        Registry.registry(
          id: "future_id",
          pid: self(),
          delete_at: future_time,
          ttl: 1000
        )

      Registry.insert!(future_record)

      assert Cleaner.clean_expired_states!() == :ok
      assert length(:ets.tab2list(@table_name)) == 1
    end

    test "bumps delete_at time for records with alive processes" do
      now = System.os_time(:millisecond)
      past_time = now - 5000
      ttl = 1000

      expired_record =
        Registry.registry(
          id: "alive_expired",
          pid: self(),
          delete_at: past_time,
          ttl: ttl
        )

      Registry.insert!(expired_record)

      Cleaner.clean_expired_states!()

      assert [{:registry, "alive_expired", _pid, delete_at, _ttl}] =
               :ets.lookup(@table_name, "alive_expired")

      assert delete_at >= now + ttl
    end

    test "deletes expired records with dead processes" do
      now = System.os_time(:millisecond)
      past_time = now - 5000
      id = "dead_expired"

      dead_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      registry_record =
        Registry.registry(
          id: id,
          pid: dead_pid,
          delete_at: past_time,
          ttl: 1000
        )

      Registry.insert!(registry_record)

      binary_state = :erlang.term_to_binary(%{key: "value"})
      assert {:ok, "OK"} = Redis.command(["SET", id, binary_state, "EX", "86400"])

      Process.exit(dead_pid, :kill)
      ref = Process.monitor(dead_pid)

      assert_receive {:DOWN, ^ref, :process, ^dead_pid, _}, 1000

      assert Cleaner.clean_expired_states!() == :ok
      assert :ets.tab2list(@table_name) == []
      assert LiveStash.TestRedisConn.snapshot().store[id] == nil
    end

    test "handles mixed alive and dead processes" do
      now = System.os_time(:millisecond)
      past_time = now - 5000
      ttl = 1000

      dead_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      alive_record =
        Registry.registry(
          id: "alive_mixed",
          pid: self(),
          delete_at: past_time,
          ttl: ttl
        )

      dead_record =
        Registry.registry(
          id: "dead_mixed",
          pid: dead_pid,
          delete_at: past_time,
          ttl: ttl
        )

      Registry.insert!(alive_record)
      Registry.insert!(dead_record)

      assert {:ok, "OK"} =
               Redis.command([
                 "SET",
                 "dead_mixed",
                 :erlang.term_to_binary(%{key: "dead"}),
                 "EX",
                 "86400"
               ])

      Process.exit(dead_pid, :kill)
      ref = Process.monitor(dead_pid)

      assert_receive {:DOWN, ^ref, :process, ^dead_pid, _}, 1000

      Cleaner.clean_expired_states!()

      assert length(:ets.tab2list(@table_name)) == 1

      assert [{:registry, "alive_mixed", _pid, delete_at, _ttl}] =
               :ets.lookup(@table_name, "alive_mixed")

      assert delete_at >= now + ttl
      assert LiveStash.TestRedisConn.snapshot().store["dead_mixed"] == nil
    end

    test "handles continuation batches" do
      now = System.os_time(:millisecond)
      past_time = now - 5000
      ttl = 1000

      records =
        for i <- 1..150 do
          Registry.registry(
            id: "batch_#{i}",
            pid: self(),
            delete_at: past_time,
            ttl: ttl
          )
        end

      dead_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      dead_record =
        Registry.registry(
          id: "dead_batch",
          pid: dead_pid,
          delete_at: past_time,
          ttl: ttl
        )

      Enum.each(records, &Registry.insert!/1)
      Registry.insert!(dead_record)

      assert {:ok, "OK"} =
               Redis.command([
                 "SET",
                 "dead_batch",
                 :erlang.term_to_binary(%{key: "dead"}),
                 "EX",
                 "86400"
               ])

      Process.exit(dead_pid, :kill)
      ref = Process.monitor(dead_pid)

      assert_receive {:DOWN, ^ref, :process, ^dead_pid, _}, 1000

      assert length(:ets.tab2list(@table_name)) == 151

      Cleaner.clean_expired_states!()

      assert length(:ets.tab2list(@table_name)) == 150

      for i <- 1..150 do
        id = "batch_#{i}"
        [{:registry, ^id, _pid, delete_at, _ttl}] = :ets.lookup(@table_name, id)

        assert delete_at >= now + ttl
      end

      assert LiveStash.TestRedisConn.snapshot().store["dead_batch"] == nil
    end

    test "logs Redis DEL errors and still removes dead registry entries" do
      now = System.os_time(:millisecond)
      past_time = now - 5000
      id = "dead_with_del_error"

      dead_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      Registry.insert!(
        Registry.registry(
          id: id,
          pid: dead_pid,
          delete_at: past_time,
          ttl: 1000
        )
      )

      assert {:ok, "OK"} =
               Redis.command(["SET", id, :erlang.term_to_binary(%{key: "value"}), "EX", "86400"])

      Process.exit(dead_pid, :kill)
      ref = Process.monitor(dead_pid)
      assert_receive {:DOWN, ^ref, :process, ^dead_pid, _}, 1000

      assert :ok = LiveStash.TestRedisConn.fail_next("DEL", :timeout)

      log =
        capture_log(fn ->
          assert :ok = Cleaner.clean_expired_states!()
        end)

      assert log =~ "Failed to delete stash for #{id} in Redis"
      assert Registry.get_by_id!(id) == :not_found
      assert LiveStash.TestRedisConn.snapshot().store[id] != nil
    end
  end
end
