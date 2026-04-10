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

    test "stashes only the intersection of configured keys and present socket assigns", %{
      socket: socket
    } do
      context = socket.private.live_stash_context
      updated_context = %{context | assigns: [:username, :missing_key]}
      socket_configured = put_in(socket.private.live_stash_context, updated_context)

      stashed_socket = BrowserMemory.stash(socket_configured)

      queued_events = get_in(stashed_socket.private, [:live_temp, :push_events]) || []

      stash_event =
        Enum.find(queued_events, fn
          ["live-stash:stash-state", _payload] -> true
          _ -> false
        end)

      assert ["live-stash:stash-state", payload] = stash_event
      assert is_binary(payload["assigns"])

      settings = %{
        ttl: context.ttl,
        secret: context.secret,
        security_mode: context.security_mode
      }

      assert {:ok, recovered_assigns} =
               Serializer.decode_token(socket, payload["assigns"], settings)

      assert recovered_assigns == %{username: "tester"}
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

      stashed_state = Serializer.encode_token(socket, %{player_id: 999}, settings)

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

    test "returns :error, logs warning and pushes init-browser-memory event when token decryption fails",
         %{socket: socket} do
      socket = put_in(socket.private.live_stash_context.reconnected?, true)

      params = %{
        "liveStash" => %{
          "stashedState" => "invalid_stashed_state"
        }
      }

      socket_with_params = put_in(socket.private.connect_params, params)

      log =
        capture_log(fn ->
          assert {:error, returned_socket} = BrowserMemory.recover_state(socket_with_params)

          queued_events = get_in(returned_socket.private, [:live_temp, :push_events]) || []

          assert Enum.any?(queued_events, fn
                   ["live-stash:init-browser-memory", payload] -> payload == %{}
                   _other -> false
                 end)
        end)

      assert log =~ ":invalid"
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
