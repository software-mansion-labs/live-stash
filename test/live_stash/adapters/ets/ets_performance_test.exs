defmodule LiveStash.Adapters.ETSPerformanceTest do
  use ExUnit.Case, async: false
  use LiveStash.AdapterPerformanceSuite

  require LiveStash.Adapters.ETS.State

  alias LiveStash.Fakes
  alias LiveStash.Adapters.ETS
  alias LiveStash.Adapters.ETS.State

  @table_name Application.compile_env(:live_stash, :ets_table_name, :live_stash_server_storage)
  @secret "live_stash"

  setup do
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete(@table_name)
    end

    State.create_table!()
    :ok
  end

  def build_stash_socket(stash_id, assigns), do: ets_socket(stash_id, assigns)

  def pre_insert_state(stash_id, state) do
    ets_id = get_ets_id(stash_id, @secret)
    State.insert!(State.new(ets_id, state, ttl: 86_400))
    nil
  end

  def build_recovery_socket(stash_id, assigns, _recovery_data) do
    ets_socket(stash_id, assigns, reconnected?: true)
  end

  def adapter_stash(socket), do: ETS.stash(socket)
  def adapter_recover(socket), do: ETS.recover_state(socket)

  defp ets_socket(stash_id, assigns, opts \\ []) do
    stored_keys = Map.keys(assigns)

    Fakes.socket(
      assigns: Map.merge(%{__changed__: %{}}, assigns),
      private: %{
        live_temp: %{},
        connect_params: %{"liveStash" => %{"stashId" => stash_id}},
        live_stash_context: %ETS.Context{
          stored_keys: stored_keys,
          reconnected?: Keyword.get(opts, :reconnected?, false),
          ttl: 86_400,
          secret: Keyword.get(opts, :secret, @secret),
          id: stash_id,
          node_hint: Node.self(),
          stash_fingerprint: nil
        }
      }
    )
  end

  defp get_ets_id(stash_id, secret) do
    :crypto.hash(:sha256, stash_id <> secret)
    |> Base.encode64(padding: false)
  end
end
