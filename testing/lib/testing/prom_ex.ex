defmodule Testing.PromEx do
  @moduledoc """
  PromEx setup for load testing.

  Mounted as a plug in `TestingWeb.Endpoint` at `/metrics`. Prometheus scrapes
  this endpoint directly.

  Plugins:

    * `PromEx.Plugins.Application`     - dependency versions, app uptime
    * `PromEx.Plugins.Beam`            - schedulers, run queue, memory by type, GC
    * `PromEx.Plugins.Phoenix`         - request durations, channel events
    * `PromEx.Plugins.PhoenixLiveView` - mount / handle_event / handle_info histograms

  Stash/recover latency is intentionally not measured server-side; the load
  test driver (k6) records `phx_join` -> `phx_reply` round-trip on the client.
  """

  use PromEx, otp_app: :testing

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix,
       router: TestingWeb.Router, endpoint: TestingWeb.Endpoint},
      PromEx.Plugins.PhoenixLiveView,
      Testing.PromEx.SchedulerPlugin
    ]
  end
end
