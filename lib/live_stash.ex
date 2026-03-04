defmodule LiveStash do
  @moduledoc false

  @behaviour LiveStash.Stash

  @default_opts [mode: :server, ttl: 5 * 60 * 1000]

  defmacro __using__(opts) do
    quote do
      on_mount {LiveStash, unquote(opts)}
    end
  end

  def on_mount(opts, _params, _session, socket) do
    socket = init_stash(socket, opts)

    {:cont, socket}
  end

  def init_stash(socket, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    mode = Keyword.fetch!(opts, :mode)

    module(mode).init_stash(socket, opts)
  end

  def stash(socket, state) do
    socket
    |> get_mode()
    |> module()
    |> (& &1.stash(socket, state)).()
  end

  def stash(socket, key, value) do
    socket
    |> get_mode()
    |> module()
    |> (& &1.stash(socket, key, value)).()
  end

  def recover_state(%{private: %{live_stash_reconnected?: true}} = socket) do
    socket
    |> get_mode()
    |> module()
    |> (& &1.recover_state(socket)).()
  end

  def recover_state(_socket), do: {:new, %{}}

  def reset_stash(socket) do
    socket
    |> get_mode()
    |> module()
    |> (& &1.reset_stash(socket)).()
  end

  defp module(:server), do: LiveStash.Server
  defp module(:client), do: LiveStash.Client
  defp module(mode), do: raise(ArgumentError, "[LiveStash] Invalid mode: #{inspect(mode)}")

  defp get_mode(%{private: %{live_stash_mode: mode}}), do: mode

  defp get_mode(_) do
    raise(
      ArgumentError,
      "[LiveStash] LiveStash has not been initialized, please use on_mount/1 to initialize it"
    )
  end
end
