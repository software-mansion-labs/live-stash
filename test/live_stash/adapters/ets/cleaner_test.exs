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
      future_record = State.new("future_id", %{key: "value"}, ttl: 60)
      State.insert!(future_record)

      assert Cleaner.clean_expired_states!() == :ok
      assert length(:ets.tab2list(@table_name)) == 1
    end

    test "deletes expired records regardless of whether the owning process is alive" do
      now = System.os_time(:second)
      past_time = now - 5

      alive_record =
        State.state(
          id: "alive_expired",
          pid: self(),
          delete_at: past_time,
          state: %{key: "alive"}
        )

      dead_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      dead_record =
        State.state(
          id: "dead_expired",
          pid: dead_pid,
          delete_at: past_time,
          state: %{key: "dead"}
        )

      State.insert!(alive_record)
      State.insert!(dead_record)

      Process.exit(dead_pid, :kill)
      ref = Process.monitor(dead_pid)
      assert_receive {:DOWN, ^ref, :process, ^dead_pid, _}, 1000

      assert Cleaner.clean_expired_states!() == :ok
      assert :ets.tab2list(@table_name) == []
    end

    test "deletes only expired records when mixed with non-expired ones" do
      now = System.os_time(:second)
      past_time = now - 5

      expired_record =
        State.state(
          id: "expired",
          pid: self(),
          delete_at: past_time,
          state: %{key: "expired"}
        )

      fresh_record = State.new("fresh", %{key: "fresh"}, ttl: 60)

      State.insert!(expired_record)
      State.insert!(fresh_record)

      assert Cleaner.clean_expired_states!() == :ok

      assert :not_found == State.get_by_id!("expired")
      assert {:ok, %{key: "fresh"}} = State.get_by_id!("fresh")
    end
  end
end
