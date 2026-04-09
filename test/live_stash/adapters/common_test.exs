defmodule LiveStash.Adapters.CommonTest do
  use ExUnit.Case, async: true

  alias LiveStash.Adapters.Common
  alias Phoenix.LiveView.Socket

  describe "hash_term/1" do
    test "returns a deterministic sha256 hash binary" do
      term = %{my: "state", nested: [1, 2, 3]}
      hash1 = Common.hash_term(term)
      hash2 = Common.hash_term(term)

      assert is_binary(hash1)
      assert hash1 == hash2
      assert hash1 != Common.hash_term(%{other: "state"})
    end
  end

  describe "reconnected?/1" do
    test "returns true when _mounts is strictly greater than 0" do
      assert Common.reconnected?(%{"_mounts" => 1}) == true
      assert Common.reconnected?(%{"_mounts" => 5}) == true
    end

    test "returns false when _mounts is 0 or missing" do
      assert Common.reconnected?(%{"_mounts" => 0}) == false
      assert Common.reconnected?(%{}) == false
      assert Common.reconnected?(%{"other_key" => 1}) == false
    end
  end

  describe "maybe_put_secret/3 and fetch_secret/2" do
    test "returns attrs unchanged when session_key is nil" do
      assert Common.maybe_put_secret([some: "opts"], nil, %{}) == [some: "opts"]
    end

    test "adds hashed secret to attrs when valid session key and binary value are provided" do
      session = %{"my_secret_key" => "super_secret_value"}
      result = Common.maybe_put_secret([some: "opts"], "my_secret_key", session)

      assert result[:some] == "opts"
      assert is_binary(result[:secret])
    end

    test "raises ArgumentError when session_key is missing in session" do
      assert_raise ArgumentError, ~r/failed to return a valid secret/, fn ->
        Common.maybe_put_secret([], "missing_key", %{"other" => "val"})
      end
    end

    test "raises ArgumentError when session secret is not a binary" do
      assert_raise ArgumentError, ~r/returned an invalid type/, fn ->
        Common.maybe_put_secret([], "int_secret", %{"int_secret" => 12345})
      end
    end
  end

  describe "get_connect_params/1" do
    test "raises custom RuntimeError when get_connect_params fails" do
      socket = %Socket{}

      assert_raise RuntimeError, ~r/Failed to get connect params/, fn ->
        Common.get_connect_params(socket)
      end
    end
  end
end
