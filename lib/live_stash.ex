defmodule LiveStash do
  @moduledoc """

  LiveStash is a library that fixes problem of losing state on LiveView reconnects.
  It allows you to store and retrieve data in a LiveView application.
  """

  @behaviour LiveStash.Stash

  alias Phoenix.LiveView
  alias LiveStash.Settings
  alias LiveStash.Utils

  @internal_assigns [:__changed__, :flash, :live_action, :myself]

  def default_secret_fun(_), do: "live_stash"

  defmacro __using__(opts) do
    quote do
      on_mount({LiveStash, unquote(opts)})
    end
  end

  def on_mount(opts, _params, session, socket) do
    socket = init_stash(socket, session, opts)

    {:cont, socket}
  end

  def init_stash(socket, session, opts \\ []) do
    {secret_fun, opts} = Keyword.pop(opts, :secret_fun, &__MODULE__.default_secret_fun/1)
    evaluated_secret = evaluate_secret_fun(secret_fun, session)

    connect_params = get_connect_params(socket)
    mounts = if connect_params, do: connect_params["_mounts"], else: nil
    reconnected? = not is_nil(mounts) and mounts > 0

    settings = Settings.new(opts, reconnected?, evaluated_secret)

    mode = settings.mode

    socket
    |> LiveView.put_private(:live_stash, settings)
    |> module(mode).init_stash(session, opts)
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

  defp evaluate_secret_fun(secret_fun, socket) do
    secret =
      try do
        secret_fun.(socket)
      rescue
        e ->
          msg =
            Utils.error_message(
              "The provided secret_fun failed to return a valid secret.",
              e,
              __STACKTRACE__
            )

          reraise ArgumentError.exception(msg), __STACKTRACE__
      end

    unless is_binary(secret) do
      raise ArgumentError,
            "The provided secret_fun returned an invalid type. Expected a binary string, got: #{inspect(secret)}"
    end

    :crypto.hash(:sha256, secret)
    |> Base.encode64(padding: false)
  end

  defp get_connect_params(socket) do
    try do
      LiveView.get_connect_params(socket)
    rescue
      e in RuntimeError ->
        msg =
          Utils.error_message(
            "Failed to get connect params. This likely means that LiveStash.init_stash/2 is being called outside of the mount lifecycle or before the socket is fully initialized.",
            e,
            __STACKTRACE__
          )

        reraise RuntimeError.exception(msg), __STACKTRACE__
    end
  end
end
