defmodule LiveStash.Adapters.ETSPerformanceTest do
  use ExUnit.Case, async: false
  use LiveStash.AdapterPerformanceSuite

  require LiveStash.Adapters.ETS.State

  alias LiveStash.Adapters.ETS
  alias LiveStash.Adapters.ETS.State
  alias LiveStash.PerformanceHelpers

  @table_name Application.compile_env(:live_stash, :ets_table_name, :live_stash_server_storage)
  @secret "live_stash"

  setup do
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete(@table_name)
    end

    State.create_table!()
    :ok
  end

  def build_stash_socket(stash_id, assigns) do
    PerformanceHelpers.ets_socket(stash_id, assigns)
  end

  def pre_insert_state(stash_id, state) do
    ets_id = PerformanceHelpers.get_ets_id(stash_id, @secret)
    State.insert!(State.new(ets_id, state, ttl: 86_400))
    nil
  end

  def build_recovery_socket(stash_id, assigns, _recovery_data) do
    PerformanceHelpers.ets_socket(stash_id, assigns, reconnected?: true)
  end

  def adapter_stash(socket), do: ETS.stash(socket)
  def adapter_recover(socket), do: ETS.recover_state(socket)
end
