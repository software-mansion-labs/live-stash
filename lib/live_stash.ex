defmodule LiveStash do
  @moduledoc """

  LiveStash is a library that fixes problem of losing state on LiveView reconnects.
  It allows you to store and retrieve data in a LiveView application.
  """

  @behaviour LiveStash.Stash

  alias Phoenix.LiveView
  alias LiveStash.Settings
  alias LiveStash.Utils

  require Logger

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
    settings = Settings.from_socket(socket, opts)

    socket
    |> LiveView.put_private(:live_stash_keys, MapSet.new())
    |> LiveView.put_private(:live_stash, settings)
    |> module(settings.mode).init_stash(opts)
  end

  def stash_assigns(socket, keys) when is_list(keys) do
    existing_keys = socket.private[:live_stash_keys]

    if existing_keys == nil do
      raise_not_initialized_error()
    end

    has_new_keys? = not MapSet.subset?(MapSet.new(keys), existing_keys)

    updated_socket =
      Enum.reduce(keys, socket, fn key, acc_socket ->
        value = Map.fetch!(socket.assigns, key)

        current_keys = acc_socket.private[:live_stash_keys]

        acc_socket
        |> Phoenix.LiveView.put_private(:live_stash_keys, MapSet.put(current_keys, key))
        |> stash(key, value)
      end)

    if has_new_keys? do
      stash(updated_socket, :key_list, keys)
    else
      updated_socket
    end
  rescue
    e in KeyError ->
      msg =
        Utils.reason_message(
          "Failed to stash assigns. Key #{inspect(e.key)} is missing from socket.assigns.",
          :missing
        )

      reraise RuntimeError, msg, __STACKTRACE__
  end

  def stash(socket, key, value) do
    socket
    |> get_mode()
    |> module()
    |> (& &1.stash(socket, key, value)).()
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

  defp module(mode) do
    msg =
      Utils.reason_message(
        "Invalid mode: #{inspect(mode)}",
        :invalid
      )

    raise ArgumentError, msg
  end

  defp get_mode(%{private: %{live_stash: %LiveStash.Settings{mode: mode}}}), do: mode

  defp get_mode(_) do
    raise_not_initialized_error()
  end

  defp raise_not_initialized_error() do
    msg =
      Utils.reason_message(
        "LiveStash has not been initialized, please use on_mount/1 to initialize it",
        :error
      )

    raise ArgumentError, msg
  end
end
