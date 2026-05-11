defmodule LiveStash.Adapters.Redis.HookTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias LiveStash.Adapters.Redis.{Hook, Context}
  alias LiveStash.Fakes

  setup do
    LiveStash.TestRedisConn.stop()
    {:ok, _pid} = LiveStash.TestRedisConn.start_link(name: LiveStash.Adapters.Redis.Conn)
    on_exit(fn -> LiveStash.TestRedisConn.stop() end)

    socket =
      Fakes.socket(
        private: %{
          live_temp: %{},
          lifecycle: %Phoenix.LiveView.Lifecycle{},
          live_stash_context: %Context{
            stored_keys: [],
            reconnected?: false,
            ttl: 1,
            secret: "live_stash",
            id: "test-id",
            stash_fingerprint: nil
          }
        }
      )

    {:ok, socket: socket}
  end

  describe "attach/1" do
    test "registers one handle_info hook on the socket", %{socket: socket} do
      attached = Hook.attach(socket)
      assert length(attached.private.lifecycle.handle_info) == 1
    end

    test "schedules the first keep-alive after ttl / 2 milliseconds", %{socket: socket} do
      # ttl = 1s → interval = 500ms
      Hook.attach(socket)
      assert_receive :live_stash_keep_alive, 600
    end
  end

  describe "hook callback" do
    setup %{socket: socket} do
      attached = Hook.attach(socket)
      [%{function: callback}] = attached.private.lifecycle.handle_info
      {:ok, attached: attached, callback: callback}
    end

    test "returns {:halt, socket} for the keep-alive message", %{
      attached: attached,
      callback: callback
    } do
      assert {:halt, _socket} = callback.(:live_stash_keep_alive, attached)
    end

    test "reschedules the next keep-alive after handling", %{
      attached: attached,
      callback: callback
    } do
      callback.(:live_stash_keep_alive, attached)
      assert_receive :live_stash_keep_alive, 600
    end

    test "reads the current redis key from context on each tick", %{
      attached: attached,
      callback: callback
    } do
      new_id = "rotated-id"
      updated_context = %{attached.private.live_stash_context | id: new_id}
      socket_with_new_id = put_in(attached.private.live_stash_context, updated_context)

      assert {:halt, _} = callback.(:live_stash_keep_alive, socket_with_new_id)
    end

    test "returns {:cont, socket} for non-keep-alive messages", %{
      attached: attached,
      callback: callback
    } do
      assert {:cont, ^attached} = callback.(:some_other_message, attached)
    end

    test "logs when bump_ttl fails", %{attached: attached, callback: callback} do
      LiveStash.TestRedisConn.fail_next("EXPIRE", :econnrefused)

      log =
        capture_log(fn ->
          callback.(:live_stash_keep_alive, attached)
          Process.sleep(50)
        end)

      assert log =~ "Failed to refresh stash"
    end
  end
end
