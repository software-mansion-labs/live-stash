defmodule TestingWeb.Performance.LiveStashRedisLive do
  use TestingWeb, :live_view

  use LiveStash,
    adapter: LiveStash.Adapters.Redis,
    ttl: 60,
    stored_keys: [:payload, :size_kb]

  alias TestingWeb.Performance.Payload

  def mount(params, _session, socket) do
    {status, socket} =
      socket
      |> assign(:size_kb, Payload.parse_size_kb(params))
      |> LiveStash.recover_state()
      |> case do
      {:recovered, recovered_socket} ->
        {:recovered, recovered_socket}

      {status, socket} ->
        assign_new_payload(socket)
        |> then(&{status, &1})
      end

    socket =
      socket
      |> assign(:recovered, status == :recovered)
      |> assign(Payload.byte_metrics(socket.assigns.payload))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div
      id="performance-livestash-redis"
      data-recovered={to_string(@recovered)}
      data-payload-bytes={@payload_bytes}
      data-payload-compressed-bytes={@payload_compressed_bytes}
      data-size-kb={@size_kb}
    >
      <h1>Performance (LiveStash Redis)</h1>
      <p>size_kb: {@size_kb}</p>
      <p>payload_bytes (term_to_binary): {@payload_bytes}</p>
      <p>payload_compressed_bytes: {@payload_compressed_bytes}</p>
      <p>recovered: {to_string(@recovered)}</p>
      <button phx-click="regenerate" aria-label="Regenerate">Regenerate</button>
    </div>
    """
  end

  def handle_event("regenerate", _, socket) do
    socket =
      socket
      |> assign_new_payload()
      |> LiveStash.stash()

    {:noreply, assign(socket, Payload.byte_metrics(socket.assigns.payload))}
  end

  defp assign_new_payload(socket) do
    assign(socket, :payload, Payload.generate(socket.assigns.size_kb))
  end
end
