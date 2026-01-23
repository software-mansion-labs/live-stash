defmodule LiveStash do
  @moduledoc false

  @default_opts [mode: :server, ttl: 5 * 60 * 1000]

  def on_mount(:default, _params, _session, socket) do
    {:cont, module(:server).init(socket, @default_opts)}
  end

  def on_mount(opts, _params, _session, socket) do
    opts = Keyword.merge(@default_opts, opts)
    mode = Keyword.fetch!(opts, :mode)

    {:cont, module(mode).init(socket, opts)}
  end

  defguard reconnected?(socket)
           when is_map(socket) and is_map_key(socket, :private) and is_map(socket.private) and
                  is_map_key(socket.private, :live_stash_reconnected?) and
                  socket.private.live_stash_reconnected? == true

  def stash_assign(socket, key, value) do
    mode = socket.private.live_stash_mode
    module(mode).stash_assign(socket, key, value)
  end

  def recover_state(socket) do
    mode = socket.private.live_stash_mode
    module(mode).recover_state(socket)
  end

  defp module(:server), do: LiveStash.Server
  defp module(:client), do: LiveStash.Client
  defp module(mode), do: raise(ArgumentError, "invalid mode: #{inspect(mode)}")
end
