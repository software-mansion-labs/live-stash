defmodule ShowcaseAppWeb.Perf.BrowserMemoryPerformanceLive do
  alias LiveStash.Adapters.BrowserMemory.Serializer
  use ShowcaseAppWeb, :live_view
  use LiveStash, adapter: LiveStash.Adapters.BrowserMemory, stored_keys: [:data], ttl: 86_400

  def mount(params, _session, socket) do
    {status, socket} = LiveStash.recover_state(socket)

    socket =
      case status do
        :recovered -> socket
        _ ->
          socket
          |> assign( data: generate_payload(Map.get(params, "size", "medium")))
          |> LiveStash.stash()
      end

    payload_bytes =
      Serializer.encode_token(socket, socket.assigns.data, %{security_mode: :encrypt, secret: "secret_key", ttl: 86_400})
      |> byte_size()

    socket =
      if connected?(socket) do
        socket
        |> assign(stashed: true)
      else
        assign(socket, stashed: false)
      end

    {:ok, assign(socket, status: status, payload_bytes: payload_bytes)}
  end

  def render(assigns) do
    ~H"""
    <div id="perf"
         phx-hook=".PerfMetrics"
         data-adapter="browser_memory"
         data-status={to_string(@status)}
         data-stashed={to_string(@stashed)}
         data-payload-bytes={@payload_bytes}
         data-token-bytes="">
      <p>Adapter: BrowserMemory</p>
      <p>Status: {to_string(@status)}</p>
      <p>Payload size: {@payload_bytes} bytes</p>
    </div>
    """
  end

  # BrowserMemory state travels in the WebSocket upgrade URL via LiveSocket params.
  # The signed token is URL-encoded in the HTTP request line, so payload size is
  # bounded by the server's max request-line length (Bandit default: ~10 KB).
  # ~2 KB of raw data -> ~3 KB token.
  # Larger payloads will cause "Request URI is too long" errors.
  defp generate_payload("small"), do: %{count: 1}
  defp generate_payload(_medium), do: Map.new(1..30, fn i -> {"k#{i}", String.duplicate("x", 60)} end)
end
