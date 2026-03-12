defmodule LiveStash.Client do
  @moduledoc """
  A client-side stash that persists data in the browser's memory.
  """

  @behaviour LiveStash.Stash

  require Logger

  alias LiveStash.Utils
  alias LiveStash.Serializer

  alias Phoenix.LiveView

  @impl true
  def init_stash(socket, _session, _opts) do
    reconnected? = socket.private.live_stash.reconnected?

    # If mounts is set to 0 we are on a new connection and stashed state is no longer valid
    if not reconnected? do
      LiveView.push_event(socket, "live-stash:reset", %{})
    else
      socket
    end
  end

  @impl true
  def stash(socket, key, value) do
    payload =
      Serializer.term_to_external(
        socket,
        key,
        value,
        get_settings(socket)
      )

    LiveView.push_event(socket, "live-stash:stash", payload)
  end

  @impl true
  def recover_state(socket) do
    case LiveView.get_connect_params(socket) do
      %{"stashedState" => stashed_state} when is_map(stashed_state) ->
        recovered_state = Serializer.external_to_term(socket, stashed_state, get_settings(socket))

        {:recovered, recovered_state}

      _ ->
        {:not_found, %{}}
    end
  rescue
    error ->
      handle_recovery_error(
        error,
        __STACKTRACE__,
        "Could not recover stashed state due to an unexpected error."
      )
  end

  @impl true
  def reset_stash(socket) do
    LiveView.push_event(socket, "live-stash:reset", %{})
  end

  defp handle_recovery_error(error, stacktrace, message) do
    err = Utils.error_message(message, error, stacktrace)
    Logger.error(err)

    {:error, err}
  end

  defp get_settings(socket) do
    %{
      ttl: socket.private.live_stash.ttl,
      secret: socket.private.live_stash.secret,
      security_mode: socket.private.live_stash.security_mode
    }
  end
end
