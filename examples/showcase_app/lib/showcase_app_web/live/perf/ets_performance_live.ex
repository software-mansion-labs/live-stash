defmodule ShowcaseAppWeb.Perf.ETSPerformanceLive do
  use ShowcaseAppWeb, :live_view
  use LiveStash, adapter: LiveStash.Adapters.ETS, stored_keys: [:data], ttl: 86_400

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

    words = :erts_debug.size(socket.assigns.data)
    payload_bytes = words * :erlang.system_info(:wordsize)

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
         data-adapter="ets"
         data-status={to_string(@status)}
         data-stashed={to_string(@stashed)}
         data-payload-bytes={@payload_bytes}>
      <p>Adapter: ETS</p>
      <p>Status: {to_string(@status)}</p>
      <p>Payload size: {@payload_bytes} bytes</p>
    </div>
    """
  end

  # small  — fits both adapters; comparable baseline
  # medium — fits both adapters (~2 KB); shows BrowserMemory token-transfer overhead. ~2 KB of raw data (after :erlang.binary_to_term) ->~3.6 KB in memory.
  # large  — ETS only; only a UUID travels on reconnect so payload size doesn't matter
  defp generate_payload("small"), do: %{count: 1}
  defp generate_payload("large"), do: Map.new(1..500, fn i -> {"key_#{i}", String.duplicate("x", 500)} end)
  defp generate_payload(_medium), do: Map.new(1..30, fn i -> {"k#{i}", String.duplicate("x", 60)} end)
end
