defmodule LiveStash.Adapters.MnesiaTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias LiveStash.Adapters.Mnesia
  alias LiveStash.Adapters.Mnesia.Context
  alias LiveStash.Adapters.Mnesia.State
  alias Phoenix.LiveView.Socket
  alias LiveStash.Fakes

  setup_all do
    State.setup_cluster_state!()
    on_exit(fn -> Memento.stop() end)
    :ok
  end

  setup do
    secret = "live_stash"
    stash_id = "test_uuid_1234"

    socket =
      Fakes.socket(
        assigns: %{
          __changed__: %{},
          player_id: 123,
          username: "tester"
        },
        private: %{
          live_temp: %{},
          lifecycle: %Phoenix.LiveView.Lifecycle{},
          connect_params: %{"liveStash" => %{"stashId" => stash_id}},
          live_stash_context: %Context{
            stored_keys: [:username],
            reconnected?: false,
            ttl: 86_400,
            secret: secret,
            id: stash_id,
            stash_fingerprint: nil
          }
        }
      )

    mnesia_id =
      :crypto.hash(:sha256, stash_id <> secret)
      |> Base.encode64(padding: false)

    Memento.Table.clear(LiveStash.Adapters.Mnesia.State)

    {:ok, socket: socket, mnesia_id: mnesia_id, stash_id: stash_id}
  end

  describe "init_stash/3" do
    test "rotates stashId, pushes init event and clears Mnesia when not reconnected", %{
      socket: socket,
      mnesia_id: mnesia_id,
      stash_id: stash_id
    } do
      State.insert!(State.new(mnesia_id, %{}, ttl: 86_400))

      initialized_socket = Mnesia.init_stash(socket, %{}, stored_keys: [:username])

      generated_id = initialized_socket.private.live_stash_context.id

      assert generated_id != stash_id
      assert is_binary(generated_id)

      assert State.get_by_id!(mnesia_id) == :not_found

      queued_events = get_in(initialized_socket.private, [:live_temp, :push_events]) || []

      assert Enum.any?(queued_events, fn
               ["live-stash:init-mnesia", payload] ->
                 payload.stashId == generated_id

               _other ->
                 false
             end)
    end

    test "logs error and rotates ID when Mnesia delete fails on new connection", %{
      socket: socket,
      stash_id: stash_id
    } do
      on_exit(fn -> State.setup_cluster_state!() end)

      :mnesia.delete_table(LiveStash.Adapters.Mnesia.State)

      log =
        capture_log(fn ->
          initialized_socket = Mnesia.init_stash(socket, %{}, stored_keys: [:username])

          generated_id = initialized_socket.private.live_stash_context.id
          assert generated_id != stash_id
          assert is_binary(generated_id)

          queued_events = get_in(initialized_socket.private, [:live_temp, :push_events]) || []

          assert Enum.any?(queued_events, fn
                   ["live-stash:init-mnesia", payload] ->
                     payload.stashId == generated_id

                   _other ->
                     false
                 end)
        end)

      assert log =~ "Failed to clear existing stash on new connection"
    end

    test "uses existing stashId from connect_params and does not clear Mnesia when reconnected? is true",
         %{socket: socket, mnesia_id: mnesia_id, stash_id: stash_id} do
      State.insert!(State.new(mnesia_id, %{recovered: true}, ttl: 86_400))

      socket = put_in(socket.private[:connect_params]["_mounts"], 1)

      initialized_socket = Mnesia.init_stash(socket, %{}, stored_keys: [:username])

      id_after_init = initialized_socket.private.live_stash_context.id
      assert id_after_init == stash_id
      assert initialized_socket.private.live_stash_context.reconnected? == true

      queued_events = get_in(initialized_socket.private, [:live_temp, :push_events]) || []

      assert Enum.any?(queued_events, fn
               ["live-stash:init-mnesia", payload] ->
                 payload.stashId == id_after_init

               _other ->
                 false
             end)

      assert {:ok, %{recovered: true}} = State.get_by_id!(mnesia_id)
    end
  end

  describe "stash/1" do
    test "saves specified assigns to the Mnesia table", %{socket: socket, mnesia_id: mnesia_id} do
      returned_socket = Mnesia.stash(socket)

      assert %Socket{} = returned_socket

      assert {:ok, saved_state} = State.get_by_id!(mnesia_id)
      assert saved_state == %{username: "tester"}
    end

    test "does not update Mnesia when only untracked assigns change - fingerprint remains the same",
         %{socket: socket, mnesia_id: mnesia_id} do
      stashed_socket = Mnesia.stash(socket)

      record_before =
        Memento.transaction!(fn ->
          Memento.Query.read(LiveStash.Adapters.Mnesia.State, mnesia_id)
        end)

      socket_with_untracked_change = %{
        stashed_socket
        | assigns: Map.put(stashed_socket.assigns, :player_id, 999)
      }

      Mnesia.stash(socket_with_untracked_change)

      record_after =
        Memento.transaction!(fn ->
          Memento.Query.read(LiveStash.Adapters.Mnesia.State, mnesia_id)
        end)

      assert record_before == record_after
      assert {:ok, %{username: "tester"}} = State.get_by_id!(mnesia_id)
    end

    test "updates state when stashed assigns fingerprint changes", %{
      socket: socket,
      mnesia_id: mnesia_id
    } do
      stashed_socket = Mnesia.stash(socket)

      updated_socket = put_in(stashed_socket.assigns.username, "tester-2")

      Mnesia.stash(updated_socket)

      assert {:ok, saved_state} = State.get_by_id!(mnesia_id)
      assert saved_state == %{username: "tester-2"}
    end

    test "stashes only the intersection of configured keys and present socket assigns", %{
      socket: socket,
      mnesia_id: mnesia_id
    } do
      context = socket.private.live_stash_context
      updated_context = %{context | stored_keys: [:username, :missing_key]}
      socket_configured = put_in(socket.private.live_stash_context, updated_context)

      assert %Socket{} = Mnesia.stash(socket_configured)

      assert {:ok, saved_state} = State.get_by_id!(mnesia_id)
      assert saved_state == %{username: "tester"}
    end

    test "crashes the process if attempting to stash to a record owned by a different PID", %{
      socket: socket,
      mnesia_id: mnesia_id
    } do
      Task.async(fn ->
        State.put!(mnesia_id, %{username: "detached process"}, ttl: 86_400)
      end)
      |> Task.await()

      socket_with_new_state = put_in(socket.assigns.username, "current process")

      assert_raise RuntimeError, ~r/Mnesia transaction aborted/, fn ->
        Mnesia.stash(socket_with_new_state)
      end
    end
  end

  describe "recover_state/1" do
    test "recovers state from Mnesia and updates socket assigns, keeping existing assigns", %{
      socket: socket,
      mnesia_id: mnesia_id
    } do
      socket = put_in(socket.private.live_stash_context.reconnected?, true)

      state_to_recover = %{player_level: 42, theme: "dark"}

      State.insert!(State.new(mnesia_id, state_to_recover, ttl: 86_400))

      assert {:recovered, recovered_socket} = Mnesia.recover_state(socket)

      assert recovered_socket.assigns.player_level == 42
      assert recovered_socket.assigns.theme == "dark"
      assert recovered_socket.assigns.__changed__ == %{player_level: true, theme: true}
      assert recovered_socket.assigns.player_id == 123
      assert recovered_socket.assigns.username == "tester"
    end

    test "takes ownership of the Mnesia record (updates PID) upon recovery", %{
      socket: socket,
      mnesia_id: mnesia_id
    } do
      socket = put_in(socket.private.live_stash_context.reconnected?, true)
      opts = [ttl: 86_400]

      Task.async(fn ->
        State.put!(mnesia_id, %{player_level: 10}, opts)
      end)
      |> Task.await()

      assert {:recovered, recovered_socket} = Mnesia.recover_state(socket)
      assert recovered_socket.assigns.player_level == 10

      assert State.put!(mnesia_id, %{player_level: 11}, opts) == :ok
    end

    test "returns :not_found when there is no state in Mnesia for the given id", %{socket: socket} do
      socket = put_in(socket.private.live_stash_context.reconnected?, true)

      assert {:not_found, returned_socket} = Mnesia.recover_state(socket)
      assert returned_socket == socket
    end

    test "rescues exceptions, logs error and returns {:error, socket}", %{socket: socket} do
      socket_ready = put_in(socket.private.live_stash_context.reconnected?, true)

      broken_socket = put_in(socket_ready.private.live_stash_context.secret, nil)

      log =
        capture_log(fn ->
          assert {:error, _socket} = Mnesia.recover_state(broken_socket)
        end)

      assert log =~ "Could not recover state"
    end

    test "returns :new and socket when reconnected? is false", %{socket: socket} do
      assert {:new, returned_socket} = Mnesia.recover_state(socket)
      assert returned_socket == socket
    end
  end

  describe "reset_stash/1" do
    test "deletes the state from Mnesia and clears fingerprint", %{
      socket: socket,
      mnesia_id: mnesia_id
    } do
      socket = put_in(socket.private.live_stash_context.stash_fingerprint, "some_hash_to_clear")

      State.insert!(State.new(mnesia_id, %{data: "to_be_deleted"}, ttl: 86_400))

      assert {:ok, _} = State.get_by_id!(mnesia_id)

      reset_socket = Mnesia.reset_stash(socket)

      assert %Socket{} = reset_socket
      assert reset_socket.private.live_stash_context.stash_fingerprint == nil
      assert State.get_by_id!(mnesia_id) == :not_found
    end

    test "rotates ID and pushes init event when Mnesia delete fails", %{
      socket: socket,
      stash_id: stash_id
    } do
      socket = put_in(socket.private.live_stash_context.stash_fingerprint, "some_hash_to_clear")
      broken_socket = put_in(socket.private.live_stash_context.secret, nil)

      log =
        capture_log(fn ->
          reset_socket = Mnesia.reset_stash(broken_socket)

          assert %Socket{} = reset_socket
          assert reset_socket.private.live_stash_context.stash_fingerprint == nil

          new_id = reset_socket.private.live_stash_context.id
          assert new_id != stash_id

          queued_events = get_in(reset_socket.private, [:live_temp, :push_events]) || []

          assert Enum.any?(queued_events, fn
                   ["live-stash:init-mnesia", payload] -> payload.stashId == new_id
                   _other -> false
                 end)
        end)

      assert log =~ "Failed to delete stash during reset"
    end
  end
end
