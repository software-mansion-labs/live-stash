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

      {ext_key, ext_val} = Serializer.term_to_external(socket, key, value, opts)

      assert is_binary(ext_key)
      assert is_binary(ext_val)

      stashed_state = %{ext_key => ext_val}
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

      {ext_key, ext_val} = Serializer.term_to_external(socket, key, value, opts)

      assert is_binary(ext_key)
      assert is_binary(ext_val)

      stashed_state = %{ext_key => ext_val}
      recovered = Serializer.external_to_term(socket, stashed_state, opts)

      assert recovered == %{{:player, 1} => [inventory: "sword"]}
    end
  end

  describe "external_to_term/3 error cases" do
    setup do
      {:ok, opts: %{security_mode: :sign, secret: "my_secret", ttl: 86400}}
    end

    test "ignores invalid Base64 key and logs a warning", %{socket: socket, opts: opts} do
      stashed_state = %{"broken!key" => "any_value"}

      log =
        capture_log(fn ->
          assert Serializer.external_to_term(socket, stashed_state, opts) == %{}
        end)

      assert log =~ "Could not recover a stashed item"
      assert log =~ ":invalid_base64"
    end

    test "ignores modified/corrupted token", %{socket: socket, opts: opts} do
      {ext_key, _ext_val} = Serializer.term_to_external(socket, :test_key, "data", opts)

      stashed_state = %{ext_key => "this_is_not_a_valid_token"}

      log =
        capture_log(fn ->
          assert Serializer.external_to_term(socket, stashed_state, opts) == %{}
        end)

      assert log =~ "Could not recover a stashed item"
      assert log =~ ":invalid"
    end

    test "ignores expired tokens", %{socket: socket} do
      opts = %{security_mode: :sign, secret: "my_secret", ttl: 0}
      {ext_key, ext_val} = Serializer.term_to_external(socket, :time_test, "data", opts)

      Process.sleep(1)

      stashed_state = %{ext_key => ext_val}

      log =
        capture_log(fn ->
          assert Serializer.external_to_term(socket, stashed_state, opts) == %{}
        end)

      assert log =~ "Could not recover a stashed item"
      assert log =~ ":expired"
    end

    test "recovers the rest of the state after error", %{socket: socket, opts: opts} do
      {valid_key_1, valid_val_1} =
        Serializer.term_to_external(socket, :first_item, "success_1", opts)

      {valid_key_2, valid_val_2} =
        Serializer.term_to_external(socket, :second_item, "success_2", opts)

      stashed_state = %{
        valid_key_1 => valid_val_1,
        "broken!base64!key" => "some_bad_value",
        valid_key_2 => valid_val_2
      }

      recovered =
        Serializer.external_to_term(socket, stashed_state, opts)

      assert recovered == %{
               first_item: "success_1",
               second_item: "success_2"
             }
    end
  end

  describe "security constraints (Remote Code Execution & atom exhaustion)" do
    setup do
      {:ok, opts: %{security_mode: :sign, secret: "my_secret", ttl: 86400}}
    end

    test "prevents RCE via executable terms", %{socket: socket, opts: opts} do
      malicious_function = fn -> :pwned end

      malicious_key =
        malicious_function
        |> :erlang.term_to_binary()
        |> Base.encode64()

      stashed_state = %{malicious_key => "jakakolwiek_wartosc"}

      log =
        capture_log(fn ->
          assert Serializer.external_to_term(socket, stashed_state, opts) == %{}
        end)

      assert log =~ "Could not recover a stashed item"
      assert log =~ ":invalid_term"
    end

    test "prevents Atom Exhaustion by rejecting non-existent atoms", %{socket: socket, opts: opts} do
      fake_atom_name = "hax0r_atom_#{System.unique_integer([:positive])}"

      binary_payload = <<131, 119, byte_size(fake_atom_name)::8, fake_atom_name::binary>>

      malicious_key = Base.encode64(binary_payload)

      stashed_state = %{malicious_key => "jakakolwiek_wartosc"}

      log =
        capture_log(fn ->
          assert Serializer.external_to_term(socket, stashed_state, opts) == %{}
        end)

      assert log =~ "Could not recover a stashed item"
      assert log =~ ":invalid_term"
    end
  end
end
