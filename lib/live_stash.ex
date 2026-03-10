defmodule LiveStash do
  @moduledoc false

  @behaviour LiveStash.Stash

  alias Phoenix.LiveView
  alias LiveStash.Settings

  @internal_assigns [:__changed__, :flash, :live_action, :myself]

  def default_secret_fun(_), do: "live_stash"

  defmacro __using__(opts) do
    quote do
      on_mount({LiveStash, unquote(opts)})
    end
  end

  def on_mount(opts, _params, _session, socket) do
    socket = init_stash(socket, opts)

    {:cont, socket}
  end

  def init_stash(socket, opts \\ []) do
    secret_fun = Keyword.get(opts, :secret_fun, &__MODULE__.default_secret_fun/1)
    evaluated_secret = secret_fun.(socket)

    mounts = LiveView.get_connect_params(socket)["_mounts"]
    reconnected? = not is_nil(mounts) and mounts > 0

    mode = Keyword.fetch!(opts, :mode)

    settings = Settings.new(opts, reconnected?, evaluated_secret)

    socket
    |> LiveView.put_private(:live_stash, settings)
    |> module(mode).init_stash(opts)
  end

  def stash_assigned(socket) do
    socket.assigns
    |> Map.drop(@internal_assigns)
    |> Enum.reduce(socket, fn {key, value}, acc_socket ->
      stash(acc_socket, key, value)
    end)
  end

  def stash_assigned(socket, keys) when is_list(keys) do
    Enum.reduce(keys, socket, fn key, acc_socket ->
      case Map.fetch(socket.assigns, key) do
        {:ok, value} -> stash(acc_socket, key, value)
        :error -> acc_socket
      end
    end)
  end

  def stash(socket, state) do
    Enum.reduce(state, socket, fn {key, value}, acc_socket ->
      stash(acc_socket, key, value)
    end)
  end

  def stash(socket, key, value) when is_atom(key) or is_number(key) or is_binary(key) do
    socket
    |> get_mode()
    |> module()
    |> (& &1.stash(socket, key, value)).()
  end

  def stash(_socket, key, _value) do
    raise ArgumentError,
          "Invalid stash key: #{inspect(key)}. The key can only be an atom, number, or string (binary)."
  end

  def recover_state(%{private: %{live_stash: %LiveStash.Settings{reconnected?: true}}} = socket) do
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

  defp get_mode(%{private: %{live_stash: %LiveStash.Settings{mode: mode}}}), do: mode

  defp get_mode(_) do
    raise(
      ArgumentError,
      "[LiveStash] LiveStash has not been initialized, please use on_mount/1 to initialize it"
    )
  end
end
