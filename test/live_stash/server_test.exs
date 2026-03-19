defmodule LiveStash.ServerTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  require LiveStash.Server.State

  alias LiveStash.Server
  alias LiveStash.Server.State
  alias LiveStash.Server.StateFinder
  alias Phoenix.LiveView.Socket

  @table_name Application.compile_env(:live_stash, :ets_table_name, :live_stash_server_storage)

  defmodule MockEndpoint do
    def config(:secret_key_base) do
      String.duplicate("abcdefghijklmnopqrstuvwxyz012345", 2)
    end
  end

  setup do
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete(@table_name)
    end

    State.create_table!()

    secret = "my_server_test_secret"
    stash_id = "test_uuid_1234"

    socket = %Socket{
      endpoint: MockEndpoint,
      transport_pid: self(),
      assigns: %{
        __changed__: %{},
        player_id: 123,
        username: "tester"
      },
      private: %{
        live_temp: %{},
        connect_params: %{"stashId" => stash_id},
        live_stash_id: stash_id,
        live_stash: %{
          reconnected?: false,
          ttl: 86_400,
          secret: secret,
          security_mode: :sign,
          node_hint: Node.self()
        }
      }
    }

    ets_id =
      :crypto.hash(:sha256, stash_id <> secret)
      |> Base.encode64(padding: false)

    {:ok,
     socket: socket,
     secret: secret,
     ets_id: ets_id,
     delete_at: System.os_time(:millisecond) + 86_400}
  end

  describe "init_stash/3" do
    test "assigns a new live_stash_id, pushes init event and clears ETS when not reconnected", %{
      socket: socket,
      ets_id: ets_id,
      delete_at: delete_at
    } do
      State.insert!(
        State.state(id: ets_id, pid: self(), delete_at: delete_at, ttl: 1000, state: %{})
      )

      initialized_socket = Server.init_stash(socket, %{}, [])

      generated_id = initialized_socket.private.live_stash_id

      assert is_binary(generated_id)

      assert StateFinder.get_from_cluster(ets_id, Node.self()) == :not_found

      queued_events = get_in(initialized_socket.private, [:live_temp, :push_events]) || []

      assert Enum.any?(queued_events, fn
               ["live-stash:init-server", payload] ->
                 payload.stashId == generated_id and is_binary(payload.node)

               _other ->
                 false
             end)
    end

    test "uses existing stashId from connect_params and does not clear ETS when reconnected? is true",
         %{socket: socket, ets_id: ets_id, delete_at: delete_at} do
      State.insert!(
        State.state(
          id: ets_id,
          pid: self(),
          delete_at: delete_at,
          ttl: 1000,
          state: %{recovered: true}
        )
      )

      socket =
        socket
        |> put_in([Access.key(:private), :live_stash, :reconnected?], true)
        |> put_in([Access.key(:private), :connect_params], %{"stashId" => "test_uuid_1234"})

      initialized_socket = Server.init_stash(socket, %{}, [])

      id_after_init = initialized_socket.private.live_stash_id
      assert id_after_init == "test_uuid_1234"

      queued_events = get_in(initialized_socket.private, [:live_temp, :push_events]) || []

      assert Enum.any?(queued_events, fn
               ["live-stash:init-server", payload] ->
                 payload.stashId == id_after_init and is_binary(payload.node)

               _other ->
                 false
             end)

      assert {:ok, %{recovered: true}} = StateFinder.get_from_cluster(ets_id, Node.self())
    end
  end

  describe "stash_assigns/2" do
    test "saves specified assigns to the ETS table", %{socket: socket, ets_id: ets_id} do
      returned_socket = Server.stash_assigns(socket, [:username])

      assert %Socket{} = returned_socket

      assert {:ok, saved_state} = StateFinder.get_from_cluster(ets_id, Node.self())
      assert saved_state == %{username: "tester"}
    end

    test "raises a custom RuntimeError when attempting to stash a missing key", %{socket: socket} do
      assert_raise RuntimeError, ~r/Key :missing_key is missing from socket.assigns/, fn ->
        Server.stash_assigns(socket, [:missing_key])
      end
    end
  end

  describe "recover_state/1" do
    test "recovers state from ETS and updates socket assigns, keeping existing assigns", %{
      socket: socket,
      ets_id: ets_id
    } do
      state_to_recover = %{player_level: 42, theme: "dark"}
      State.put!(ets_id, state_to_recover, ttl: 86_400)

      assert {:recovered, recovered_socket} = Server.recover_state(socket)

      assert recovered_socket.assigns.player_level == 42
      assert recovered_socket.assigns.theme == "dark"
      assert recovered_socket.assigns.__changed__ == %{player_level: true, theme: true}
      assert recovered_socket.assigns.player_id == 123
      assert recovered_socket.assigns.username == "tester"
    end

    test "returns :not_found when there is no state in ETS for the given id", %{socket: socket} do
      assert {:not_found, returned_socket} = Server.recover_state(socket)
      assert returned_socket == socket
    end

    test "rescues exceptions, logs error and returns {:error, socket}", %{socket: socket} do
      broken_socket = put_in(socket.private.live_stash, nil)

      log =
        capture_log(fn ->
          assert {:error, _socket} = Server.recover_state(broken_socket)
        end)

      assert log =~ "Could not recover state"
    end
  end

  describe "reset_stash/1" do
    test "deletes the state from ETS", %{socket: socket, ets_id: ets_id} do
      State.put!(ets_id, %{data: "to_be_deleted"}, ttl: 86_400)

      assert {:ok, _} = StateFinder.get_from_cluster(ets_id, Node.self())

      assert %Socket{} = Server.reset_stash(socket)

      assert StateFinder.get_from_cluster(ets_id, Node.self()) == :not_found
    end

    test "rescues exceptions, logs error and returns socket unchanged", %{socket: socket} do
      broken_socket = put_in(socket.private.live_stash, nil)

      log =
        capture_log(fn ->
          assert %Socket{} = Server.reset_stash(broken_socket)
        end)

      assert log =~ "Could not reset stash"
    end
  end
end
