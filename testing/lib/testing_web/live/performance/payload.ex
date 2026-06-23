defmodule TestingWeb.Performance.Payload do
  @moduledoc false

  def parse_size_kb(%{"size_kb" => str}) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  def parse_size_kb(_), do: 1

  def generate(size_kb) when is_integer(size_kb) and size_kb > 0 do
    target_bytes = size_kb * 1024
    id = System.unique_integer([:positive])
    generated_at = System.system_time(:millisecond)

    base = %{
      id: id,
      generated_at: generated_at,
      settings: settings(),
      items: []
    }

    grow_to_target(base, target_bytes)
  end

  def measure_bytes(payload) do
    byte_size(:erlang.term_to_binary(payload))
  end

  def measure_compressed_bytes(payload) do
    byte_size(:erlang.term_to_binary(payload, [{:compressed, 1}]))
  end

  def byte_metrics(payload) do
    %{
      payload_bytes: measure_bytes(payload),
      payload_compressed_bytes: measure_compressed_bytes(payload)
    }
  end

  defp settings do
    %{
      theme: :system,
      locale: "en-US",
      page: 1,
      per_page: 25,
      filters: %{
        status: "active",
        category: "general",
        sort_by: "updated_at",
        sort_dir: :desc
      },
      notifications: %{
        email: true,
        push: false,
        digest: "daily"
      }
    }
  end

  defp build_item(index, id, generated_at) do
    %{
      id: index,
      session_id: id,
      title: "Item #{index}",
      status: Enum.at(["active", "pending", "archived"], rem(index, 3)),
      updated_at: generated_at + index,
      tags: ["tag-#{rem(index, 5)}", "category-#{rem(index, 7)}"],
      attributes: %{
        quantity: rem(index, 100) + 1,
        sku: "SKU-#{Integer.to_string(id, 36)}-#{index}",
        notes: item_notes(index)
      }
    }
  end

  defp item_notes(index) do
    "Updated workflow step #{index} with validation rules, copy, and field metadata."
  end

  defp grow_to_target(payload, target_bytes) do
    current = measure_bytes(payload)

    if current >= target_bytes do
      payload
    else
      index = length(payload.items)
      item = build_item(index, payload.id, payload.generated_at)
      grow_to_target(%{payload | items: payload.items ++ [item]}, target_bytes)
    end
  end
end
