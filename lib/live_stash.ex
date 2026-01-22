defmodule LiveStash do
  @moduledoc false

  @default_opts [mode: :server, ttl: 5 * 60 * 1000, stashed_assigns: []]

  def on_mount(:default, _params, _session, socket) do
    {:cont, init(socket, @default_opts)}
  end

  def on_mount(opts, _params, _session, socket) do
    opts = Keyword.merge(@default_opts, opts)
    {:cont, init(socket, opts)}
  end

  defp init(socket, opts) do
    mode = Keyword.fetch!(opts, :mode)

    case mode do
      :server -> LiveStash.Server.init(socket, opts)
      :client -> LiveStash.Client.init(socket, opts)
      _ -> raise(ArgumentError, "invalid mode: #{inspect(mode)}")
    end
  end
end
