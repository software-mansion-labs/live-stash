defmodule LiveStash do
  @moduledoc false

  @behaviour LiveStash.Stash

  @default_opts [mode: :server, ttl: 5 * 60 * 1000]

  @impl true
  def init_stash(socket, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    mode = Keyword.fetch!(opts, :mode)

    module(mode).init_stash(socket, opts)
  end

  @impl true
  def stash_assign(socket, key, value) do
    socket
    |> get_mode()
    |> module()
    |> (& &1.stash_assign(socket, key, value)).()
  end

  @impl true
  def recover_state(%{private: %{live_stash_reconnected?: true}} = socket) do
    socket
    |> get_mode()
    |> module()
    |> (& &1.recover_state(socket)).()
  end

  def recover_state(socket), do: {:new, socket}

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
