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
            reconnected?: false,
            ttl: 86_400,
            secret: secret,
            security_mode: :sign,
            key_set: MapSet.new([:player_id])
          }
        }
      )

    {:ok, socket: socket, secret: secret}
  end

  describe "init_stash/3" do
    test "does not push reset event if reconnected? is true", %{socket: socket} do
      socket = put_in(socket.private[:connect_params], %{"_mounts" => 1})

      result_socket = BrowserMemory.init_stash(socket, %{}, [])

      assert result_socket.private.live_stash_context.reconnected? == true

      events = result_socket.private |> Map.get(:live_temp, %{}) |> Map.get(:push_events, [])

      refute Enum.any?(events, fn [event, _payload] ->
               event == "live-stash:init-browser-memory"
             end)
    end

    test "resets state and initializes empty live_stash_keys when reconnected? is false", %{
      socket: socket
    } do
      socket = put_in(socket.private.live_stash_context.reconnected?, false)

      initialized_socket = BrowserMemory.init_stash(socket, %{}, [])

      assert initialized_socket.private.live_stash_context.key_set == MapSet.new()
      assert %Socket{} = initialized_socket
    end
  end

  describe "stash/2" do
    test "updates live_stash_keys with new keys and pushes stash event", %{socket: socket} do
      assert MapSet.member?(socket.private.live_stash_context.key_set, :player_id)
      refute MapSet.member?(socket.private.live_stash_context.key_set, :username)

      stashed_socket = BrowserMemory.stash(socket, [:username])

      assert MapSet.member?(stashed_socket.private.live_stash_context.key_set, :player_id)
      assert MapSet.member?(stashed_socket.private.live_stash_context.key_set, :username)
      assert %Socket{} = stashed_socket

      queued_events = get_in(stashed_socket.private, [:live_temp, :push_events]) || []

      assert Enum.any?(queued_events, fn
               ["live-stash:stash-state", payload] ->
                 is_map(payload) and Map.has_key?(payload, "assigns") and
                   Map.has_key?(payload, "keys")

               _other ->
                 false
             end)
    end

    test "raises a custom RuntimeError when attempting to stash a missing key", %{socket: socket} do
      assert_raise RuntimeError, ~r/Key :missing_key is missing from socket.assigns/, fn ->
        BrowserMemory.stash(socket, [:missing_key])
      end
    end
  end

  describe "recover_state/1" do
    test "recovers assigns and updates live_stash_keys when connect_params contain valid stashedState",
         %{socket: socket} do
      socket = put_in(socket.private.live_stash_context.reconnected?, true)

      settings = %{
        ttl: 86_400,
        secret: socket.private.live_stash_context.secret,
        security_mode: :sign
      }

      stashed_keys = Serializer.term_to_external(socket, [:player_id], settings)
      {ext_key_1, ext_val_1} = Serializer.term_to_external(socket, :player_id, 999, settings)

      params = %{
        "liveStash" => %{
          "stashedState" => %{
            "keys" => stashed_keys,
            "assigns" => %{
              ext_key_1 => ext_val_1
            }
          }
        }
      }

      socket_with_params = put_in(socket.private.connect_params, params)

      assert {:recovered, recovered_socket} = BrowserMemory.recover_state(socket_with_params)

      assert recovered_socket.assigns.player_id == 999
      assert recovered_socket.assigns.username == "tester"

      assert recovered_socket.private.live_stash_context.key_set == MapSet.new([:player_id])
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
          "stashedState" => %{
            "keys" => "invalid_keys_token",
            "assigns" => %{}
          }
        }
      }

      socket_with_params = put_in(socket.private.connect_params, params)

      log =
        capture_log(fn ->
          assert {:error, _socket} = BrowserMemory.recover_state(socket_with_params)
        end)

      assert log =~ "Failed to retrieve key set"
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
    test "pushes reset event and clears live_stash_keys", %{socket: socket} do
      reset_socket = BrowserMemory.reset_stash(socket)

      assert %Socket{} = reset_socket
      assert reset_socket.private.live_stash_context.key_set == MapSet.new()

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
