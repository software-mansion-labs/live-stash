defmodule LiveStash.SerializerTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias LiveStash.Serializer
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

  describe ":sign mode" do
    setup do
      {:ok, opts: %{security_mode: :sign, secret: "my_signing_secret", ttl: 86400}}
    end

    test "correctly serializes and deserializes data", %{socket: socket, opts: opts} do
      key = :my_key
      value = %{points: 42, active: true}

      %{key_hash: key_hash, key: ext_key, value: ext_val} =
        Serializer.term_to_external(socket, key, value, opts)

      assert is_binary(key_hash)
      assert is_binary(ext_key)
      assert is_binary(ext_val)

      stashed_state = %{key_hash => %{"key" => ext_key, "value" => ext_val}}
      recovered = Serializer.external_to_term(socket, stashed_state, opts)

      assert recovered == %{my_key: %{points: 42, active: true}}
    end
  end

  describe ":encrypt mode" do
    setup do
      {:ok, opts: %{security_mode: :encrypt, secret: "my_encryption_secret", ttl: 86400}}
    end

    test "correctly encrypts and decrypts data", %{socket: socket, opts: opts} do
      key = {:player, 1}
      value = [inventory: "sword"]

      %{key_hash: key_hash, key: ext_key, value: ext_val} =
        Serializer.term_to_external(socket, key, value, opts)

      assert is_binary(key_hash)
      assert is_binary(ext_key)
      assert is_binary(ext_val)

      stashed_state = %{key_hash => %{"key" => ext_key, "value" => ext_val}}
      recovered = Serializer.external_to_term(socket, stashed_state, opts)

      assert recovered == %{{:player, 1} => [inventory: "sword"]}
    end
  end

  describe "external_to_term/3 error cases" do
    setup do
      {:ok, opts: %{security_mode: :sign, secret: "my_secret", ttl: 86400}}
    end

    test "ignores failed decoding and logs a warning", %{socket: socket, opts: opts} do
      stashed_state = %{
        "broken!key!hash" => %{"key" => "some_bad_key", "value" => "some_bad_value"}
      }

      log =
        capture_log(fn ->
          assert Serializer.external_to_term(socket, stashed_state, opts) == %{}
        end)

      assert log =~ "Could not recover a stashed item"
      assert log =~ ":invalid"
    end

    test "ignores malformed stashed state and logs a warning", %{socket: socket, opts: opts} do
      %{key_hash: _key_hash, key: ext_key, value: _ext_val} =
        Serializer.term_to_external(socket, :test_key, "data", opts)

      stashed_state = %{ext_key => "this_is_not_a_valid_token"}

      log =
        capture_log(fn ->
          assert Serializer.external_to_term(socket, stashed_state, opts) == %{}
        end)

      assert log =~ "Malformed stashed state item received from client"
      assert log =~ ":invalid"
    end

    test "ignores expired tokens", %{socket: socket} do
      opts = %{security_mode: :sign, secret: "my_secret", ttl: 0}

      %{key_hash: key_hash, key: ext_key, value: ext_val} =
        Serializer.term_to_external(socket, :time_test, "data", opts)

      Process.sleep(1)

      stashed_state =
        %{key_hash => %{"key" => ext_key, "value" => ext_val}}

      log =
        capture_log(fn ->
          assert Serializer.external_to_term(socket, stashed_state, opts) == %{}
        end)

      assert log =~ "Could not recover a stashed item"
      assert log =~ ":expired"
    end

    test "recovers the rest of the state after error", %{socket: socket, opts: opts} do
      %{key_hash: key_hash_1, key: valid_key_1, value: valid_val_1} =
        Serializer.term_to_external(socket, :first_item, "success_1", opts)

      %{key_hash: key_hash_2, key: valid_key_2, value: valid_val_2} =
        Serializer.term_to_external(socket, :second_item, "success_2", opts)

      stashed_state = %{
        key_hash_1 => %{"key" => valid_key_1, "value" => valid_val_1},
        "broken!base64!key" => %{"key" => "some_bad_key", "value" => "some_bad_value"},
        key_hash_2 => %{"key" => valid_key_2, "value" => valid_val_2}
      }

      recovered =
        Serializer.external_to_term(socket, stashed_state, opts)

      assert recovered == %{
               first_item: "success_1",
               second_item: "success_2"
             }
    end
  end
end
