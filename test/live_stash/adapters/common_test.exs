defmodule LiveStash.Adapters.CommonTest do
  use ExUnit.Case, async: true

  alias LiveStash.Adapters.Common
  alias LiveStash.Fakes
  alias Phoenix.LiveView.Socket

  describe "rotate_id/1" do
    test "replaces id with a new unique binary, preserving other context fields" do
      socket =
        Fakes.socket(
          private: %{live_stash_context: %{id: "old-id", stash_fingerprint: "fp", ttl: 1}}
        )

      updated = Common.rotate_id(socket)

      assert updated.private.live_stash_context.id != "old-id"
      assert is_binary(updated.private.live_stash_context.id)
      assert updated.private.live_stash_context.stash_fingerprint == "fp"
      assert updated.private.live_stash_context.ttl == 1
    end

    test "generates a different id on each call" do
      socket = Fakes.socket(private: %{live_stash_context: %{id: "old-id"}})

      id1 = Common.rotate_id(socket).private.live_stash_context.id
      id2 = Common.rotate_id(socket).private.live_stash_context.id

      assert id1 != id2
    end
  end

  describe "clear_fingerprint/1" do
    test "sets stash_fingerprint to nil, preserving other context fields" do
      socket =
        Fakes.socket(
          private: %{live_stash_context: %{id: "my-id", stash_fingerprint: "some-fp", ttl: 1}}
        )

      updated = Common.clear_fingerprint(socket)

      assert updated.private.live_stash_context.stash_fingerprint == nil
      assert updated.private.live_stash_context.id == "my-id"
      assert updated.private.live_stash_context.ttl == 1
    end

    test "is a no-op when fingerprint is already nil" do
      socket =
        Fakes.socket(private: %{live_stash_context: %{id: "my-id", stash_fingerprint: nil}})

      updated = Common.clear_fingerprint(socket)

      assert updated.private.live_stash_context.stash_fingerprint == nil
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
        Common.maybe_put_secret([], "int_secret", %{"int_secret" => 123})
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

  describe "validate_attributes!/2" do
    @allowed_keys [
      :stored_keys,
      :reconnected?,
      :stash_fingerprint,
      :secret,
      :ttl,
      :id,
      :security_mode
    ]

    test "returns attributes when all are valid and allowed" do
      attrs = [ttl: 1, stored_keys: [:username], secret: "sec", reconnected?: false]
      assert Common.validate_attributes!(attrs, @allowed_keys) == attrs
    end

    test "raises ArgumentError for invalid ttl type" do
      assert_raise ArgumentError, ~r/Invalid ttl/, fn ->
        Common.validate_attributes!([ttl: "1"], @allowed_keys)
      end
    end

    test "raises ArgumentError for invalid stored_keys type" do
      assert_raise ArgumentError, ~r/Invalid stored_keys/, fn ->
        Common.validate_attributes!([stored_keys: ["username"]], @allowed_keys)
      end
    end

    test "raises ArgumentError for invalid secret type" do
      assert_raise ArgumentError, ~r/Invalid secret/, fn ->
        Common.validate_attributes!([secret: 123], @allowed_keys)
      end
    end

    test "raises ArgumentError for invalid stash_fingerprint type" do
      assert_raise ArgumentError, ~r/Invalid stash_fingerprint/, fn ->
        Common.validate_attributes!([stash_fingerprint: 123], @allowed_keys)
      end
    end

    test "raises ArgumentError for invalid id type" do
      assert_raise ArgumentError, ~r/Invalid id/, fn ->
        Common.validate_attributes!([id: 123], @allowed_keys)
      end
    end

    test "raises ArgumentError for invalid security_mode type" do
      assert_raise ArgumentError, ~r/Invalid security_mode/, fn ->
        Common.validate_attributes!([security_mode: :unknown], @allowed_keys)
      end
    end

    test "raises ArgumentError for unknown attributes" do
      assert_raise ArgumentError, ~r/Unknown attribute passed/, fn ->
        Common.validate_attributes!([unknown_attr: true], @allowed_keys)
      end
    end
  end
end
