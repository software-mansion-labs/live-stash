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

  describe "term_to_external/3" do
    setup do
      {:ok, opts: %{security_mode: :sign, secret: "my_signing_secret", ttl: 86_400}}
    end

    test "correctly encodes a raw value into a token", %{socket: socket, opts: opts} do
      value = [:key_1, :key_2]
      encoded = Serializer.term_to_external(socket, value, opts)

      assert is_binary(encoded)

      assert {:ok, ^value} = Phoenix.Token.verify(socket, opts.secret, encoded, max_age: opts.ttl)
    end
  end

  describe ":sign mode" do
    setup do
      {:ok, opts: %{security_mode: :sign, secret: "my_signing_secret", ttl: 86_400}}
    end

    test "correctly serializes and deserializes data", %{socket: socket, opts: opts} do
      key = :my_key
      value = %{points: 42, active: true}

      {ext_key, ext_val} =
        Serializer.term_to_external(socket, key, value, opts)

      assert is_binary(ext_key)
      assert is_binary(ext_val)

      stashed_keys = Serializer.term_to_external(socket, [key], opts)
      stashed_state = %{ext_key => ext_val}

      assert {:ok, {recovered, key_set}} =
               Serializer.external_to_term(socket, stashed_state, stashed_keys, opts)

      assert recovered == %{my_key: %{points: 42, active: true}}
      assert key_set == MapSet.new([:my_key])
    end
  end

  describe ":encrypt mode" do
    setup do
      {:ok, opts: %{security_mode: :encrypt, secret: "my_encryption_secret", ttl: 86_400}}
    end

    test "correctly encrypts and decrypts data", %{socket: socket, opts: opts} do
      key = {:player, 1}
      value = [inventory: "sword"]

      {ext_key, ext_val} =
        Serializer.term_to_external(socket, key, value, opts)

      assert is_binary(ext_key)
      assert is_binary(ext_val)

      stashed_keys = Serializer.term_to_external(socket, [key], opts)
      stashed_state = %{ext_key => ext_val}

      assert {:ok, {recovered, key_set}} =
               Serializer.external_to_term(socket, stashed_state, stashed_keys, opts)

      assert recovered == %{{:player, 1} => [inventory: "sword"]}
      assert key_set == MapSet.new([{:player, 1}])
    end
  end

  describe "external_to_term/4 error cases" do
    setup do
      {:ok, opts: %{security_mode: :sign, secret: "my_secret", ttl: 86_400}}
    end

    test "returns an error if stashed_keys cannot be decoded", %{socket: socket, opts: opts} do
      assert {:error, msg} = Serializer.external_to_term(socket, %{}, "invalid_keys_token", opts)

      assert msg =~ "Failed to retrieve key set from stashed keys"
      assert msg =~ "invalid"
    end

    test "returns an error if an item is missing from stashed_state", %{
      socket: socket,
      opts: opts
    } do
      stashed_keys = Serializer.term_to_external(socket, [:test_key], opts)

      assert {:error, msg} = Serializer.external_to_term(socket, %{}, stashed_keys, opts)
      assert msg =~ "Failed to decode stashed assign with key :test_key"
    end

    test "returns an error if a stashed_state token is invalid", %{socket: socket, opts: opts} do
      stashed_keys = Serializer.term_to_external(socket, [:test_key], opts)
      {ext_key, _ext_val} = Serializer.term_to_external(socket, :test_key, "data", opts)

      stashed_state = %{ext_key => "invalid_token_for_value"}

      assert {:error, msg} =
               Serializer.external_to_term(socket, stashed_state, stashed_keys, opts)

      assert msg =~ "Failed to decode stashed assign with key :test_key"
    end
  end
end
