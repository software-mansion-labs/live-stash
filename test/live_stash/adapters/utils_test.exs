defmodule LiveStash.UtilsTest do
  use ExUnit.Case, async: true

  alias LiveStash.Utils

  describe "hash_term/1" do
    test "returns a deterministic sha256 hash binary" do
      term = %{my: "state", nested: [1, 2, 3]}
      hash1 = Utils.hash_term(term)
      hash2 = Utils.hash_term(term)

      assert is_binary(hash1)
      assert hash1 == hash2
      assert hash1 != Utils.hash_term(%{other: "state"})
    end
  end
end
