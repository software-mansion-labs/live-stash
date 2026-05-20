defmodule TestingWeb.Performance.Payload do
  @moduledoc false

  @term_overhead_bytes 64

  def parse_size_kb(%{"size_kb" => str}) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  def parse_size_kb(_), do: 1

  def generate(size_kb) when is_integer(size_kb) and size_kb > 0 do
    target_bytes = size_kb * 1024
    data_size = max(target_bytes - @term_overhead_bytes, 1)

    %{
      id: System.unique_integer([:positive]),
      generated_at: System.system_time(:millisecond),
      data: :crypto.strong_rand_bytes(data_size)
    }
  end

  def measure_bytes(payload) do
    byte_size(:erlang.term_to_binary(payload, [{:compressed, 1}]))
  end
end
