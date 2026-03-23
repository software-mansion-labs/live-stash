defmodule LiveStash.ClientTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias LiveStash.Client
  alias LiveStash.Serializer
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
          live_stash_keys: MapSet.new([:player_id]),
          live_stash: %{
            reconnected?: false,
            ttl: 86_400,
            secret: secret,
            security_mode: :sign
          }
        }
      )

    {:ok, socket: socket, secret: secret}
  end

  describe "init_stash/3" do
    test "returns the socket unchanged if reconnected? is true", %{socket: socket} do
      socket = put_in(socket.private.live_stash.reconnected?, true)

      assert Client.init_stash(socket, %{}, []) == socket
    end

    test "resets state and initializes empty live_stash_keys when reconnected? is false", %{
      socket: socket
    } do
      socket = put_in(socket.private.live_stash.reconnected?, false)

      initialized_socket = Client.init_stash(socket, %{}, [])

      assert initialized_socket.private.live_stash_keys == MapSet.new()
      assert %Socket{} = initialized_socket
    end
  end

  describe "stash_assigns/2" do
    test "updates live_stash_keys with new keys and pushes stash event", %{socket: socket} do
      assert MapSet.member?(socket.private.live_stash_keys, :player_id)
      refute MapSet.member?(socket.private.live_stash_keys, :username)

      stashed_socket = Client.stash_assigns(socket, [:username])

      assert MapSet.member?(stashed_socket.private.live_stash_keys, :player_id)
      assert MapSet.member?(stashed_socket.private.live_stash_keys, :username)
      assert %Socket{} = stashed_socket

      queued_events = get_in(stashed_socket.private, [:live_temp, :push_events]) || []

      assert Enum.any?(queued_events, fn
               ["live-stash:stash-state", payload] ->
                 is_map(payload) and Map.has_key?(payload, :assigns) and
                   Map.has_key?(payload, :keys)

               _other ->
                 false
             end)
    end

    test "raises a custom RuntimeError when attempting to stash a missing key", %{socket: socket} do
      assert_raise RuntimeError, ~r/Key :missing_key is missing from socket.assigns/, fn ->
        Client.stash_assigns(socket, [:missing_key])
      end
    end
  end

  describe "recover_state/1" do
    test "recovers assigns and updates live_stash_keys when connect_params contain valid stashedState",
         %{socket: socket} do
      settings = %{ttl: 86_400, secret: socket.private.live_stash.secret, security_mode: :sign}

      stashed_keys = Serializer.term_to_external(socket, [:player_id], settings)
      {ext_key_1, ext_val_1} = Serializer.term_to_external(socket, :player_id, 999, settings)

      params = %{
        "stashedState" => %{
          "keys" => stashed_keys,
          "assigns" => %{
            ext_key_1 => ext_val_1
          }
        }
      }

      socket_with_params = put_in(socket.private.connect_params, params)

      assert {:recovered, recovered_socket} = Client.recover_state(socket_with_params)

      assert recovered_socket.assigns.player_id == 999
      assert recovered_socket.assigns.username == "tester"

      assert recovered_socket.private.live_stash_keys == MapSet.new([:player_id])
    end

    test "returns :not_found when connect_params do not contain stashedState", %{socket: socket} do
      assert {:not_found, returned_socket} = Client.recover_state(socket)
      assert returned_socket == socket
    end

    test "returns :error and logs warning when token decryption fails", %{socket: socket} do
      params = %{
        "stashedState" => %{
          "keys" => "invalid_keys_token",
          "assigns" => %{}
        }
      }

      socket_with_params = put_in(socket.private.connect_params, params)

      log =
        capture_log(fn ->
          assert {:error, _socket} = Client.recover_state(socket_with_params)
        end)

      assert log =~ "Failed to retrieve key set"
    end

    test "rescues generic exceptions, logs them and returns :error", %{socket: socket} do
      broken_socket = Map.delete(socket, :private)

      log =
        capture_log(fn ->
          assert {:error, _socket} = Client.recover_state(broken_socket)
        end)

      assert log =~ "Could not recover stashed state due to an unexpected error"
    end
  end

  describe "reset_stash/1" do
    test "pushes reset event and clears live_stash_keys", %{socket: socket} do
      reset_socket = Client.reset_stash(socket)

      assert %Socket{} = reset_socket
      assert reset_socket.private.live_stash_keys == MapSet.new()

      queued_events = get_in(reset_socket.private, [:live_temp, :push_events]) || []

      assert Enum.any?(queued_events, fn
               ["live-stash:reset-state", payload] ->
                 payload == %{}

               _other ->
                 false
             end)
    end
  end
end
