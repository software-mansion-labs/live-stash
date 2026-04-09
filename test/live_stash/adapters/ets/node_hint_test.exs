defmodule LiveStash.Adapters.ETS.NodeHintTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias LiveStash.Adapters.ETS
  alias LiveStash.Adapters.ETS.NodeHint
  alias LiveStash.Fakes

  setup do
    secret = "my_test_secret"

    socket =
      Fakes.socket(
        private: %{
          connect_params: %{},
          live_stash_context: %ETS.Context{
            assigns: [:username],
            secret: secret,
            id: "test_stash_id",
            reconnected?: false
          }
        }
      )

    {:ok, socket: socket, secret: secret}
  end

  describe "create_node_hint/1" do
    test "encrypts the current node using the socket's secret", %{socket: socket, secret: secret} do
      hint = NodeHint.create_node_hint(socket)

      assert is_binary(hint)

      assert {:ok, decrypted_node} = Phoenix.Token.decrypt(socket, secret, hint)
      assert decrypted_node == :erlang.atom_to_binary(Node.self())
    end
  end

  describe "get_node_hint/3" do
    test "decrypts a valid node hint and returns the node as an atom", %{
      socket: socket,
      secret: secret
    } do
      node_binary = :erlang.atom_to_binary(Node.self())
      valid_hint = Phoenix.Token.encrypt(socket, secret, node_binary)

      params = %{"liveStash" => %{"node" => valid_hint}}

      assert NodeHint.get_node_hint(socket, params, secret) == Node.self()
    end

    test "returns nil when connect_params is nil", %{socket: socket, secret: secret} do
      assert NodeHint.get_node_hint(socket, nil, secret) == nil
    end

    test "returns nil when the 'node' key is missing from connect_params", %{
      socket: socket,
      secret: secret
    } do
      params = %{"some_other_key" => "value"}
      assert NodeHint.get_node_hint(socket, params, secret) == nil
    end

    test "returns nil and logs a warning when decryption fails (invalid token)", %{
      socket: socket,
      secret: secret
    } do
      params = %{"liveStash" => %{"node" => "invalid_or_tampered_token"}}

      log =
        capture_log(fn ->
          assert NodeHint.get_node_hint(socket, params, secret) == nil
        end)

      assert log =~ "Failed to decode node hint"
    end

    test "returns nil and logs a warning when decrypted node is not an existing atom", %{
      socket: socket,
      secret: secret
    } do
      non_existent_atom_string = "non_existent_node_xyz_123456789"
      hint = Phoenix.Token.encrypt(socket, secret, non_existent_atom_string)

      params = %{"liveStash" => %{"node" => hint}}

      log =
        capture_log(fn ->
          assert NodeHint.get_node_hint(socket, params, secret) == nil
        end)

      assert log =~ "Failed to decode node hint"
    end
  end
end
