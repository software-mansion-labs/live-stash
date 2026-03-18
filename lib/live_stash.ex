defmodule LiveStash do
  @moduledoc """

  LiveStash is a library that fixes problem of losing state on LiveView reconnects.
  It allows you to store and retrieve data in a LiveView application.
  """

  @behaviour LiveStash.Stash

  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView
  alias LiveStash.Settings
  alias LiveStash.Utils

  require Logger

  @type recovery_status :: :recovered | :not_found | :new | :error

  defmacro __using__(opts) do
    quote do
      on_mount({LiveStash, unquote(opts)})
    end
  end

  @doc """
  Calls init_stash/3 to initialize the stash for a LiveView with the given options.
  """
  def on_mount(opts, _params, session, socket) do
    socket = init_stash(socket, session, opts)

    {:cont, socket}
  end

  @doc """
  Initializes the stash for a LiveView. This function is called on every mount of the LiveView in on_mount. It should not be called directly. Use on_mount/1 to initialize the stash.
  """
  @spec init_stash(socket :: Socket.t(), session :: Keyword.t(), opts :: Keyword.t()) ::
          Socket.t()
  def init_stash(socket, session, opts \\ []) do
    settings = Settings.from_socket(socket, session, opts)

    socket
    |> LiveView.put_private(:live_stash, settings)
    |> module(settings.mode).init_stash(session, opts)
  end

  @doc """
  Stashes the specified assigns from the socket. Every key in keys list must be an atom and must be present in `socket.assigns`. Assigns should be stashed consequently to ensure that the stashed state is consistent with the state of the LiveView.
  ## Examples
      def handle_event("increment", _, socket) do
        socket
        |> assign(:count, socket.assigns.count + 1)
        |> stash_assigns([:count])
        |> then(&{:noreply, &1})  end
  """
  @spec stash_assigns(socket :: Socket.t(), keys :: [atom()]) :: Socket.t()
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

  @doc """
  Recovers socket updated with the stashed state for a LiveView. This function should be called during mount. The state is not cleared after recovery.

  ## Examples
      def mount(_params, _session, socket) do
        socket
        |> recover_state()
        |> case do
          {:recovered, recovered_socket} ->
            recovered_socket
          _ -> start_new_game(socket)
        end
        |> then(&{:ok, &1})
      end
  """
  @spec recover_state(socket :: Socket.t()) :: {recovery_status(), Socket.t()}
  def recover_state(%{private: %{live_stash: %LiveStash.Settings{reconnected?: true}}} = socket) do
    socket
    |> get_mode()
    |> module()
    |> apply(:recover_state, [socket])
  end

  def recover_state(socket), do: {:new, socket}

  @doc """
  Resets the stashed state for a LiveView.

  ## Examples
      def mount(_params, _session, socket) do
        socket
        |> recover_state()
        |> case do
          {:recovered, recovered_socket} ->
            recovered_socket
          _ -> init_assigns(socket)
        end
        |> reset_stash()  # in case you want to clear the stashed state after recovery
        |> then(&{:ok, &1})
      end
  """
  @spec reset_stash(socket :: Socket.t()) :: Socket.t()
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
    msg =
      Utils.reason_message(
        "LiveStash has not been initialized, please use on_mount/1 to initialize it",
        :error
      )

    raise ArgumentError, msg
  end
end
