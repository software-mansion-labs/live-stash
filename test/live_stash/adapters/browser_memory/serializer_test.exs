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
    test "token payload is a compressed binary, not the raw term", %{socket: socket} do
      opts = %{security_mode: :sign, secret: "my_secret", ttl: 86_400}
      value = %{key: "value"}

      token = Serializer.encode_token(socket, value, opts)
      {:ok, payload} = Phoenix.Token.verify(socket, opts.secret, token, max_age: opts.ttl)

      assert is_binary(payload)
      refute payload == value
    end

    test "round-trip preserves large nested structures", %{socket: socket} do
      opts = %{security_mode: :sign, secret: "my_secret", ttl: 86_400}

      large_value = %{
        users: Enum.map(1..100, fn i -> %{id: i, name: "user_#{i}", active: rem(i, 2) == 0} end)
      }

      token = Serializer.encode_token(socket, large_value, opts)
      assert {:ok, ^large_value} = Serializer.decode_token(socket, token, opts)
    end

    test "compressed token is smaller than uncompressed for repetitive data", %{socket: socket} do
      opts = %{security_mode: :sign, secret: "my_secret", ttl: 86_400}
      repetitive = Enum.map(1..50, fn i -> %{id: i, status: :active, score: i * 10} end)

      compressed_token = Serializer.encode_token(socket, repetitive, opts)

      uncompressed_payload = :erlang.term_to_binary(repetitive)
      uncompressed_token = Phoenix.Token.sign(socket, opts.secret, uncompressed_payload, max_age: opts.ttl)

      assert byte_size(compressed_token) < byte_size(uncompressed_token)
    end

    test "returns error when decoding a pre-compression token (no backwards compat)", %{socket: socket} do
      opts = %{security_mode: :sign, secret: "my_secret", ttl: 86_400}

      # Simulate an old token that stored the raw term directly (before compression was added)
      old_token = Phoenix.Token.sign(socket, opts.secret, %{key: "value"}, max_age: opts.ttl)

      assert {:error, :invalid} = Serializer.decode_token(socket, old_token, opts)
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
