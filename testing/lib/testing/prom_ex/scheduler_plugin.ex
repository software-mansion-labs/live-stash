defmodule Testing.PromEx.SchedulerPlugin do
  @moduledoc """
  Average BEAM scheduler utilization as a Prometheus gauge (0..1).

  Schedulers can spin while idle, so OS CPU% lies for the BEAM.
  `scheduler_wall_time` tracks actual busy time per scheduler -- the honest
  CPU saturation signal.
  """

  use PromEx.Plugin

  @event [:testing, :scheduler_utilization]
  @sample_key :"#{__MODULE__}.last_sample"

  @impl true
  def polling_metrics(opts) do
    Polling.build(
      :testing_scheduler_polling_metrics,
      Keyword.get(opts, :poll_rate, 5_000),
      {__MODULE__, :sample, []},
      [
        last_value(
          [:testing, :scheduler, :utilization, :average],
          event_name: @event,
          measurement: :average,
          description: "Average normal scheduler utilization (0..1). Dirty CPU/IO schedulers excluded."
        )
      ]
    )
  end

  def sample do
    :erlang.system_flag(:scheduler_wall_time, true)
    new = :erlang.statistics(:scheduler_wall_time)

    case Process.get(@sample_key) do
      nil ->
        :ok

      old ->
        ratios =
          Enum.zip(old, new)
          |> Enum.map(fn {{_, a1, t1}, {_, a2, t2}} ->
            if t2 - t1 == 0, do: 0.0, else: (a2 - a1) / (t2 - t1)
          end)

        :telemetry.execute(@event, %{average: Enum.sum(ratios) / length(ratios)})
    end

    Process.put(@sample_key, new)
  end
end
