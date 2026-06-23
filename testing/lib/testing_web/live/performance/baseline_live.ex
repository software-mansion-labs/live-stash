defmodule TestingWeb.Performance.BaselineLive do
  use TestingWeb, :live_view

  alias TestingWeb.Performance.Payload

  def mount(params, _session, socket) do
    size_kb = Payload.parse_size_kb(params)
    payload = Payload.generate(size_kb)

    socket =
      socket
      |> assign(:size_kb, size_kb)
      |> assign(:payload, payload)
      |> assign(Payload.byte_metrics(payload))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div
      id="performance-baseline"
      data-recovered="false"
      data-payload-bytes={@payload_bytes}
      data-payload-compressed-bytes={@payload_compressed_bytes}
      data-size-kb={@size_kb}
    >
      <h1>Performance baseline (no LiveStash)</h1>
      <p>size_kb: {@size_kb}</p>
      <p>payload_bytes (term_to_binary): {@payload_bytes}</p>
      <p>payload_compressed_bytes: {@payload_compressed_bytes}</p>
      <p>payload: {inspect(@payload, pretty: true, limit: :infinity)}</p>
      <button phx-click="regenerate" aria-label="Regenerate">Regenerate</button>
    </div>
    """
  end

  def handle_event("regenerate", _, socket) do
    payload = Payload.generate(socket.assigns.size_kb)

    socket =
      socket
      |> assign(:payload, payload)
      |> assign(Payload.byte_metrics(payload))

    {:noreply, socket}
  end
end
