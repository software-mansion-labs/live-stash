defmodule LiveStash.Adapters.ETS.HookTest do
  use ExUnit.Case, async: false

  require LiveStash.Adapters.ETS.State

  alias LiveStash.Adapters.ETS.{Context, Helpers, Hook, State}
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

  describe "attach/1" do
    test "registers one handle_info hook on the socket", %{socket: socket} do
      attached = Hook.attach(socket)
      assert length(attached.private.lifecycle.handle_info) == 1
    end

    test "schedules the first keep-alive after ttl / 2 milliseconds", %{socket: socket} do
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

    test "returns {:halt, socket} for the keep-alive message and bumps the TTL", %{
      attached: attached,
      callback: callback
    } do
      context = attached.private.live_stash_context
      ets_id = Helpers.ets_id(context.id, context.secret)

      State.insert!(State.state(id: ets_id, pid: self(), delete_at: 0, state: %{}))

      assert {:halt, _socket} = callback.(:live_stash_keep_alive, attached)

      now = System.os_time(:second)
      [{:state, ^ets_id, _pid, delete_at, _}] = :ets.lookup(@table_name, ets_id)
      assert delete_at >= now
    end

    test "reschedules the next keep-alive after handling", %{
      attached: attached,
      callback: callback
    } do
      callback.(:live_stash_keep_alive, attached)
      assert_receive :live_stash_keep_alive, 600
    end

    test "reads the current ets id from context on each tick", %{
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
  end
end
