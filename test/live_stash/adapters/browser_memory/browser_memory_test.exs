defmodule LiveStash.Adapters.BrowserMemoryTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias LiveStash.Adapters.BrowserMemory
  alias LiveStash.Adapters.BrowserMemory.Serializer
  alias Phoenix.LiveView.Socket
  alias LiveStash.Fakes

  setup do
    secret = "my_client_test_secret"

    socket =
      Fakes.socket(
        assigns: %{
          __changed__: %{},
          player_id: 123,
          username: "tester"
        },
        private: %{
          live_temp: %{},
          connect_params: %{},
          live_stash_context: %BrowserMemory.Context{
            assigns: [:player_id],
            reconnected?: false,
            ttl: 86_400,
            secret: secret,
            security_mode: :sign,
            stash_fingerprint: nil
          }
        }
      )

    {:ok, socket: socket, secret: secret}
  end

  describe "init_stash/3" do
    test "does not push reset event if reconnected? is true", %{socket: socket} do
      socket = put_in(socket.private[:connect_params], %{"_mounts" => 1})

      result_socket = BrowserMemory.init_stash(socket, %{}, assigns: [:player_id])

      assert result_socket.private.live_stash_context.reconnected? == true

      events = result_socket.private |> Map.get(:live_temp, %{}) |> Map.get(:push_events, [])

      refute Enum.any?(events, fn [event, _payload] ->
               event == "live-stash:init-browser-memory"
             end)
    end

    test "pushes init event when reconnected? is false", %{
      socket: socket
    } do
      socket = put_in(socket.private.live_stash_context.reconnected?, false)

      initialized_socket = BrowserMemory.init_stash(socket, %{}, assigns: [:player_id])

      queued_events = get_in(initialized_socket.private, [:live_temp, :push_events]) || []

      assert Enum.any?(queued_events, fn
               ["live-stash:init-browser-memory", payload] -> payload == %{}
               _other -> false
             end)

      assert %Socket{} = initialized_socket
    end
  end

  describe "stash/1" do
    test "pushes stash event with serialized assigns string", %{socket: socket} do
      stashed_socket = BrowserMemory.stash(socket)

      assert %Socket{} = stashed_socket

      queued_events = get_in(stashed_socket.private, [:live_temp, :push_events]) || []

      assert Enum.any?(queued_events, fn
               ["live-stash:stash-state", payload] ->
                 is_map(payload) and is_binary(payload["assigns"])

               _other ->
                 false
             end)
    end

    test "does not push stash event when fingerprint did not change", %{socket: socket} do
      stashed_socket = BrowserMemory.stash(socket)

      new_socket =
        %{
          stashed_socket
          | assigns: Map.put(stashed_socket.assigns, :username, "changed-but-not-stashed")
        }

      stashed_again_socket = BrowserMemory.stash(new_socket)

      queued_events = get_in(stashed_again_socket.private, [:live_temp, :push_events]) || []

      stash_events_count =
        Enum.count(queued_events, fn
          ["live-stash:stash-state", _payload] -> true
          _ -> false
        end)

      assert stash_events_count == 1
    end

    test "gracefully handles missing configured keys", %{socket: socket} do
      context = socket.private.live_stash_context
      updated_context = %{context | assigns: [:missing_key]}
      updated_private = Map.put(socket.private, :live_stash_context, updated_context)
      socket_with_missing_key_context = %{socket | private: updated_private}

      stashed_socket = BrowserMemory.stash(socket_with_missing_key_context)

      queued_events = get_in(stashed_socket.private, [:live_temp, :push_events]) || []

      assert Enum.any?(queued_events, fn
               ["live-stash:stash-state", payload] ->
                 is_map(payload) and is_binary(payload["assigns"])

               _other ->
                 false
             end)
    end
  end

  describe "recover_state/1" do
    test "recovers assigns when connect_params contain valid stashedState",
         %{socket: socket} do
      socket = put_in(socket.private.live_stash_context.reconnected?, true)

      settings = %{
        ttl: 86_400,
        secret: socket.private.live_stash_context.secret,
        security_mode: :sign
      }

      stashed_state = Serializer.term_to_external(socket, %{player_id: 999}, settings)

      params = %{
        "liveStash" => %{
          "stashedState" => stashed_state
        }
      }

      socket_with_params = put_in(socket.private.connect_params, params)

      assert {:recovered, recovered_socket} = BrowserMemory.recover_state(socket_with_params)

      assert recovered_socket.assigns.player_id == 999
      assert recovered_socket.assigns.username == "tester"
    end

    test "returns :not_found when connect_params do not contain stashedState", %{socket: socket} do
      socket = put_in(socket.private.live_stash_context.reconnected?, true)

      assert {:not_found, returned_socket} = BrowserMemory.recover_state(socket)
      assert returned_socket == socket
    end

    test "returns :error and logs warning when token decryption fails", %{socket: socket} do
      socket = put_in(socket.private.live_stash_context.reconnected?, true)

      params = %{
        "liveStash" => %{
          "stashedState" => "invalid_stashed_state"
        }
      }

      socket_with_params = put_in(socket.private.connect_params, params)

      log =
        capture_log(fn ->
          assert {:error, _socket} = BrowserMemory.recover_state(socket_with_params)
        end)

      assert log =~ "Failed to decode stashed state from token"
    end

    test "rescues generic exceptions, logs them and returns :error", %{socket: socket} do
      socket_ready_to_recover = put_in(socket.private.live_stash_context.reconnected?, true)
      broken_socket = update_in(socket_ready_to_recover.private, &Map.delete(&1, :connect_params))

      log =
        capture_log(fn ->
          assert {:error, _socket} = BrowserMemory.recover_state(broken_socket)
        end)

      assert log =~ "Could not recover stashed state due to an unexpected error"
    end

    test "returns :new and socket when reconnected? is false", %{socket: socket} do
      assert {:new, returned_socket} = BrowserMemory.recover_state(socket)
      assert returned_socket == socket
    end
  end

  describe "reset_stash/1" do
    test "pushes reset event and clears fingerprint", %{socket: socket} do
      socket = put_in(socket.private.live_stash_context.stash_fingerprint, "some_hash_to_clear")

      reset_socket = BrowserMemory.reset_stash(socket)

      assert %Socket{} = reset_socket
      assert reset_socket.private.live_stash_context.stash_fingerprint == nil

      queued_events = get_in(reset_socket.private, [:live_temp, :push_events]) || []

      assert Enum.any?(queued_events, fn
               ["live-stash:init-browser-memory", payload] ->
                 payload == %{}

               _other ->
                 false
             end)
    end
  end
end
