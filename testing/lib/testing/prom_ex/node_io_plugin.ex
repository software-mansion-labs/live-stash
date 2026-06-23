defmodule Testing.PromEx.NodeIoPlugin do
  @moduledoc """
  PromEx plugin for Node.IO metrics.
  """

  use PromEx.Plugin

  @event [:testing, :port_io, :dist]

  @impl true
  def polling_metrics(opts) do
    Polling.build(:node_io_polling_metrics, Keyword.get(opts, :poll_rate, 5_000), {__MODULE__, :sample, []}, [
      last_value([:testing, :port_io, :dist, :input], event_name: @event, measurement: :input),
      last_value([:testing, :port_io, :dist, :output], event_name: @event, measurement: :output),
    ])
  end

  def sample do
    {input, output} =
      :erlang.system_info(:dist_ctrl)
      |> Enum.reduce({0, 0}, fn
        {_node, port}, {r, s} when is_port(port) ->
          case :inet.getstat(port, [:recv_oct, :send_oct]) do
            {:ok, recv_oct: ro, send_oct: so} -> {r + ro, s + so}
            _ -> {r, s}
          end
        _, acc -> acc
      end)

    :telemetry.execute(@event, %{input: input, output: output})
  end
end
