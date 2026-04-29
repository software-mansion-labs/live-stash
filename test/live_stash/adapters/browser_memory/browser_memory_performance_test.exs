defmodule LiveStash.Adapters.BrowserMemoryPerformanceTest do
  use ExUnit.Case, async: false
  use LiveStash.AdapterPerformanceSuite

  alias LiveStash.Adapters.BrowserMemory
  alias LiveStash.PerformanceHelpers

  def build_stash_socket(_stash_id, assigns) do
    PerformanceHelpers.browser_memory_socket(assigns)
  end

  def pre_insert_state(_stash_id, state) do
    socket = PerformanceHelpers.browser_memory_socket(state)
    stashed = BrowserMemory.stash(socket)

    events = get_in(stashed.private, [:live_temp, :push_events]) || []

    ["live-stash:stash-state", %{"assigns" => token}] =
      Enum.find(events, fn [event, _] -> event == "live-stash:stash-state" end)

    token
  end

  def build_recovery_socket(_stash_id, assigns, token) do
    PerformanceHelpers.browser_memory_socket(assigns)
    |> put_in(
      [Access.key!(:private), :live_stash_context, Access.key!(:reconnected?)],
      true
    )
    |> put_in(
      [Access.key!(:private), :connect_params],
      %{"liveStash" => %{"stashedState" => token}}
    )
  end

  def adapter_stash(socket), do: BrowserMemory.stash(socket)
  def adapter_recover(socket), do: BrowserMemory.recover_state(socket)
end
