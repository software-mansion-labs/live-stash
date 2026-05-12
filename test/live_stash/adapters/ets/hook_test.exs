defmodule LiveStash.Adapters.ETS.HookTest do
  use ExUnit.Case, async: false

  require LiveStash.Adapters.ETS.State

  alias LiveStash.Adapters.ETS.{Context, Hook, State}
  alias LiveStash.Fakes

  @table_name Application.compile_env(:live_stash, :ets_table_name, :live_stash_server_storage)

  setup do
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete(@table_name)
    end

    State.create_table!()

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

  describe "attach/2" do
    test "registers one handle_info hook on the socket", %{socket: socket} do
      attached = Hook.attach(socket, fn _ -> "ignored" end)
      assert length(attached.private.lifecycle.handle_info) == 1
    end

    test "schedules the first keep-alive after ttl / 2 milliseconds", %{socket: socket} do
      Hook.attach(socket, fn _ -> "ignored" end)
      assert_receive :live_stash_keep_alive, 600
    end
  end

  describe "hook callback" do
    setup %{socket: socket} do
      attached = Hook.attach(socket, fn _ -> "ets-id" end)
      [%{function: callback}] = attached.private.lifecycle.handle_info
      {:ok, attached: attached, callback: callback}
    end

    test "returns {:halt, socket} for the keep-alive message and bumps the TTL", %{
      attached: attached,
      callback: callback
    } do
      State.insert!(State.state(id: "ets-id", pid: self(), delete_at: 0, state: %{}))

      assert {:halt, _socket} = callback.(:live_stash_keep_alive, attached)

      now = System.os_time(:second)
      [{:state, "ets-id", _pid, delete_at, _}] = :ets.lookup(@table_name, "ets-id")
      assert delete_at >= now
    end

    test "reschedules the next keep-alive after handling", %{
      attached: attached,
      callback: callback
    } do
      callback.(:live_stash_keep_alive, attached)
      assert_receive :live_stash_keep_alive, 600
    end

    test "uses the ets_id derived from the socket on each tick", %{
      socket: socket
    } do
      test_pid = self()

      attached =
        Hook.attach(socket, fn sock ->
          send(test_pid, {:resolving_for, sock.private.live_stash_context.id})
          "any-id"
        end)

      [%{function: callback}] = attached.private.lifecycle.handle_info

      callback.(:live_stash_keep_alive, attached)
      assert_receive {:resolving_for, "test-id"}
    end

    test "returns {:cont, socket} for non-keep-alive messages", %{
      attached: attached,
      callback: callback
    } do
      assert {:cont, ^attached} = callback.(:some_other_message, attached)
    end
  end
end
