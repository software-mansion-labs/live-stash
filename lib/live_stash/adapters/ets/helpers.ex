defmodule LiveStash.Adapters.ETS.Helpers do
  @moduledoc false

  @doc """
  Computes the ETS primary key for the given stash `id` and `secret`.
  """
  @spec ets_id(binary(), binary()) :: binary()
  def ets_id(id, secret) do
    raw_key = id <> secret
    hashed_binary = :crypto.hash(:sha256, raw_key)
    Base.encode64(hashed_binary, padding: false)
  end
end
