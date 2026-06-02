defmodule Testing.PromEx.LiveStashPlugin do
  @moduledoc """
  PromEx plugin for LiveStash stash and recover_state telemetry.

  Metrics:

    * `live_stash_stash_called_total`   - every LiveStash.stash/1 call
    * `live_stash_stash_executed_total` - calls that actually persisted changed state
    * `live_stash_recover_state_total`  - recover_state/1 calls, broken down by status

  Labels: `adapter`, `live_view_module`.
  """

  use PromEx.Plugin

  @stash_called_event [:live_stash, :stash, :called]
  @stash_executed_event [:live_stash, :stash, :executed]
  @recover_event [:live_stash, :recover_state]

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :live_stash_stash_event_metrics,
        [
          counter(
            [:live_stash, :stash, :called, :total],
            event_name: @stash_called_event,
            measurement: :count,
            description: "Total LiveStash.stash/1 calls.",
            tag_values: &stash_tags/1,
            tags: [:adapter, :live_view_module]
          ),
          counter(
            [:live_stash, :stash, :executed, :total],
            event_name: @stash_executed_event,
            measurement: :count,
            description: "LiveStash.stash/1 calls that wrote changed state.",
            tag_values: &stash_tags/1,
            tags: [:adapter, :live_view_module]
          )
        ]
      ),
      Event.build(
        :live_stash_recover_event_metrics,
        [
          counter(
            [:live_stash, :recover_state, :total],
            event_name: @recover_event,
            measurement: :count,
            description: "LiveStash.recover_state/1 calls by outcome.",
            tag_values: &recover_tags/1,
            tags: [:adapter, :live_view_module, :status]
          )
        ]
      )
    ]
  end

  defp stash_tags(%{adapter: adapter, live_view_module: mod}) do
    %{adapter: adapter_name(adapter), live_view_module: inspect(mod)}
  end

  defp recover_tags(%{adapter: adapter, live_view_module: mod, status: status}) do
    %{adapter: adapter_name(adapter), live_view_module: inspect(mod), status: status}
  end

  defp adapter_name(LiveStash.Adapters.ETS), do: "ets"
  defp adapter_name(LiveStash.Adapters.BrowserMemory), do: "browser_memory"
  defp adapter_name(LiveStash.Adapters.Redis), do: "redis"
  defp adapter_name(LiveStash.Adapters.Mnesia), do: "mnesia"
  defp adapter_name(other), do: inspect(other)
end
