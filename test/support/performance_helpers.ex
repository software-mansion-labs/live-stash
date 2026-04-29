defmodule LiveStash.PerformanceHelpers do
  @moduledoc false

  alias LiveStash.Fakes
  alias LiveStash.Adapters.ETS
  alias LiveStash.Adapters.BrowserMemory

  def measure_ms(fun) do
    {microseconds, result} = :timer.tc(fun)
    {microseconds / 1_000, result}
  end

  def large_binary(byte_count), do: :binary.copy("x", byte_count)

  def large_map(key_count) do
    Map.new(1..key_count, fn i ->
      {String.to_atom("perf_key_#{i}"), String.duplicate("v", 200)}
    end)
  end

  @doc """
  Builds a fake socket wired for the ETS adapter.

  Options:
    - `:secret` (default `"live_stash"`)
    - `:reconnected?` (default `false`)
  """
  def ets_socket(stash_id, assigns, opts \\ []) do
    secret = Keyword.get(opts, :secret, "live_stash")
    reconnected? = Keyword.get(opts, :reconnected?, false)
    stored_keys = Map.keys(assigns)

    Fakes.socket(
      assigns: Map.merge(%{__changed__: %{}}, assigns),
      private: %{
        live_temp: %{},
        connect_params: %{"liveStash" => %{"stashId" => stash_id}},
        live_stash_context: %ETS.Context{
          stored_keys: stored_keys,
          reconnected?: reconnected?,
          ttl: 86_400,
          secret: secret,
          id: stash_id,
          node_hint: Node.self(),
          stash_fingerprint: nil
        }
      }
    )
  end

  @doc """
  Builds a fake socket wired for the BrowserMemory adapter.

  Options:
    - `:secret` (default `"perf_test_secret"`)
    - `:security_mode` (default `:sign`)
  """
  def browser_memory_socket(assigns, opts \\ []) do
    secret = Keyword.get(opts, :secret, "perf_test_secret")
    security_mode = Keyword.get(opts, :security_mode, :sign)
    stored_keys = Map.keys(assigns)

    Fakes.socket(
      assigns: Map.merge(%{__changed__: %{}}, assigns),
      private: %{
        live_temp: %{},
        connect_params: %{},
        live_stash_context: %BrowserMemory.Context{
          stored_keys: stored_keys,
          reconnected?: false,
          ttl: 86_400,
          secret: secret,
          security_mode: security_mode,
          stash_fingerprint: nil
        }
      }
    )
  end

  def get_ets_id(stash_id, secret) do
    :crypto.hash(:sha256, stash_id <> secret)
    |> Base.encode64(padding: false)
  end
end
