defmodule LiveStash.Adapters.MnesiaTest do
  use ExUnit.Case, async: false

  alias LiveStash.Adapters.Mnesia
  alias LiveStash.Adapters.Mnesia.Context
  alias LiveStash.Adapters.Mnesia.Database.State
  alias LiveStash.Fakes

  setup do
    State.create_table!()

    socket =
      Fakes.socket(
        assigns: %{
          __changed__: %{},
          player_id: 123,
          username: "tester"
        },
        private: %{
          live_temp: %{},
          connect_params: %{"liveStash" => %{"stashId" => "test_uuid_1234"}},
          live_stash_context: %Context{
            stored_keys: [:username],
            reconnected?: false,
            ttl: 86_400,
            secret: "live_stash",
            id: "test_uuid_1234",
            stash_fingerprint: nil
          }
        }
      )

    mnesia_id =
      :crypto.hash(:sha256, "test_uuid_1234" <> "live_stash")
      |> Base.encode64(padding: false)

    State.delete_by_id!(mnesia_id)

    {:ok, socket: socket, mnesia_id: mnesia_id}
  end

  test "stash/1 persists the configured assigns", %{socket: socket, mnesia_id: mnesia_id} do
    stashed_socket = Mnesia.stash(socket)

    assert %{private: %{live_stash_context: %{stash_fingerprint: fingerprint}}} = stashed_socket
    assert is_binary(fingerprint)
    assert {:ok, %{username: "tester"}} = State.get_by_id!(mnesia_id)
  end

  test "recover_state/1 restores the stashed assigns", %{socket: socket, mnesia_id: mnesia_id} do
    assert :ok = State.put!(mnesia_id, %{username: "recovered"}, ttl: 86_400)

    reconnecting_socket = put_in(socket.private.live_stash_context.reconnected?, true)

    assert {:recovered, recovered_socket} = Mnesia.recover_state(reconnecting_socket)
    assert recovered_socket.assigns.username == "recovered"
    assert :not_found == State.get_by_id!(mnesia_id)
  end

  test "reset_stash/1 clears the stored state", %{socket: socket, mnesia_id: mnesia_id} do
    assert :ok = State.put!(mnesia_id, %{username: "recovered"}, ttl: 86_400)

    assert %Phoenix.LiveView.Socket{} = Mnesia.reset_stash(socket)
    assert :not_found == State.get_by_id!(mnesia_id)
  end
end
