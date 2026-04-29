defmodule LiveStash.PerformanceHelpers do
  @moduledoc false

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
end
