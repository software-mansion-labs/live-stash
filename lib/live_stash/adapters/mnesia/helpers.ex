defmodule LiveStash.Adapters.Mnesia.Helpers do
  @moduledoc false

  @doc """
  Computes the Mnesia primary key for the given stash `id` and `secret`.
  """
  @spec mnesia_id(binary(), binary()) :: binary()
  def mnesia_id(id, secret) do
    raw_key = id <> secret
    hashed_binary = :crypto.hash(:sha256, raw_key)
    Base.encode64(hashed_binary, padding: false)
  end
end
