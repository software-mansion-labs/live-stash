defmodule LiveStash.Adapters.BrowserMemory.SerializerTest do
  use ExUnit.Case, async: true

  alias LiveStash.Adapters.BrowserMemory.Serializer
  alias Phoenix.LiveView.Socket

  defmodule MockEndpoint do
    def config(:secret_key_base) do
      String.duplicate("abcdefghijklmnopqrstuvwxyz012345", 2)
    end
  end

  setup do
    socket = %Socket{endpoint: MockEndpoint, assigns: %{}}
    {:ok, socket: socket}
  end

  describe "serialization round-trip (encode_token and decode_token)" do
    test "works correctly in :sign mode", %{socket: socket} do
      opts = %{security_mode: :sign, secret: "my_signing_secret", ttl: 86_400}
      original_state = %{my_key: %{points: 42, active: true}}

      token = Serializer.encode_token(socket, original_state, opts)
      assert is_binary(token)

      assert {:ok, ^original_state} =
               Phoenix.Token.verify(socket, opts.secret, token, max_age: opts.ttl)

      assert {:ok, ^original_state} = Serializer.decode_token(socket, token, opts)
    end

    test "works correctly in :encrypt mode", %{socket: socket} do
      opts = %{security_mode: :encrypt, secret: "my_encryption_secret", ttl: 86_400}
      original_state = %{{:player, 1} => [inventory: "sword"]}

      token = Serializer.encode_token(socket, original_state, opts)
      assert is_binary(token)

      assert {:ok, ^original_state} = Serializer.decode_token(socket, token, opts)
    end
  end

  describe "error handling" do
    test "returns an error if token cannot be decoded or is malformed", %{socket: socket} do
      opts = %{security_mode: :sign, secret: "my_secret", ttl: 86_400}

      assert {:error, :invalid} =
               Serializer.decode_token(socket, "invalid_or_malformed_token", opts)
    end

    test "returns an error for expired tokens", %{socket: socket} do
      opts = %{security_mode: :sign, secret: "my_secret", ttl: 1}

      token = Serializer.encode_token(socket, %{time_test: "data"}, opts)

      Process.sleep(2000)

      assert {:error, :expired} = Serializer.decode_token(socket, token, opts)
    end
  end
end
