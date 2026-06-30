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

  describe "compression" do
    test "compressed token is smaller than uncompressed for repetitive data", %{socket: socket} do
      opts = %{security_mode: :sign, secret: "my_secret", ttl: 86_400}
      repetitive = Enum.map(1..50, fn i -> %{id: i, status: :active, score: i * 10} end)

      compressed_token = Serializer.encode_token(socket, repetitive, opts)

      uncompressed_payload = :erlang.term_to_binary(repetitive)

      uncompressed_token =
        Phoenix.Token.sign(socket, opts.secret, uncompressed_payload, max_age: opts.ttl)

      assert byte_size(compressed_token) < byte_size(uncompressed_token)
    end
  end

  describe "error handling" do
    test "returns an error if token cannot be decoded or is malformed", %{socket: socket} do
      opts = %{security_mode: :sign, secret: "my_secret", ttl: 86_400}

      assert {:error, :invalid} =
               Serializer.decode_token(socket, "invalid_or_malformed_token", opts)
    end

    test "returns :not_found for expired tokens", %{socket: socket} do
      opts = %{security_mode: :sign, secret: "my_secret", ttl: 1}

      token = Serializer.encode_token(socket, %{time_test: "data"}, opts)

      Process.sleep(2000)

      assert :not_found = Serializer.decode_token(socket, token, opts)
    end
  end
end
