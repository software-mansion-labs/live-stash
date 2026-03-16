defmodule LiveStash do
  @moduledoc """

  LiveStash is a library that fixes problem of losing state on LiveView reconnects.
  It allows you to store and retrieve data in a LiveView application.
  """

  @behaviour LiveStash.Stash

  alias Phoenix.LiveView
  alias Phoenix.Component
  alias LiveStash.Settings
  alias LiveStash.Utils

  require Logger

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
    settings = Settings.from_socket(socket, session, opts)

    socket
    |> LiveView.put_private(:live_stash, settings)
    |> module(settings.mode).init_stash(session, opts)
  end

  def stash_assigns(socket, keys) when is_list(keys) do
    socket
    |> get_mode()
    |> module()
    |> apply(:stash_assigns, [socket, keys])
  end

  def stash_assigns(_socket, _keys) do
    msg =
      Utils.reason_message(
        "Keys must be a list of atoms",
        :invalid
      )

    raise ArgumentError, msg
  end

  def stash(socket, key, value) do
    socket
    |> get_mode()
    |> module()
    |> apply(:stash, [socket, key, value])
  end

  def recover_state(%{private: %{live_stash: %LiveStash.Settings{reconnected?: true}}} = socket) do
    recovered_state =
      socket
      |> get_mode()
      |> module()
      |> apply(:recover_state, [socket])

    case recovered_state do
      {:recovered, state} ->
        {:recovered, Component.assign(socket, state)}

      {status, _state} ->
        {status, socket}
    end
  end

  def recover_state(socket), do: {:new, socket}

  def reset_stash(socket) do
    socket
    |> get_mode()
    |> module()
    |> apply(:reset_stash, [socket])
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
    Utils.raise_uninitialized_error()
  end
end
