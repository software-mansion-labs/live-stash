defmodule LiveStash.Client do
  @moduledoc """
  A client-side stash that persists data in the browser's memory.
  """

  @behaviour LiveStash.Stash

  require Logger

  alias LiveStash.Utils

  alias Phoenix.LiveView

  @impl true
  def init_stash(socket, _opts) do
    mounts = LiveView.get_connect_params(socket)["_mounts"]
    reconnected? = not is_nil(mounts) and mounts > 0

    # If mounts is set to 0 we are on a new connection and stashed state is no longer valid
    if not reconnected? do
      LiveView.push_event(socket, "live-stash:reset", %{})
    end

    socket
    |> LiveView.put_private(:live_stash_mode, :client)
    |> LiveView.put_private(:live_stash_reconnected?, reconnected?)
  end

  @impl true
  def stash(socket, key, value) do
    encoded_value =
    value
    |> :erlang.term_to_binary()
    |> Base.encode64()

    encoded_key =
    key
    |> :erlang.term_to_binary()
    |> Base.encode64()

    dbg([encoded_key, encoded_value])
    LiveView.push_event(socket, "live-stash:stash", %{key: encoded_key, value: encoded_value})
  end

  @impl true
  def recover_state(socket) do
    case LiveView.get_connect_params(socket) do
      %{"stashedState" => stashed_state} ->
        dbg(stashed_state)
        parsed_state = parse_state(stashed_state)
        dbg(parsed_state)
        {:recovered, parsed_state}
      _ ->
        {:not_found, %{}}
    end
  rescue
    error in [ArgumentError, FunctionClauseError] ->
      handle_recovery_error(error, __STACKTRACE__, "Could not recover stashed state. Error when decoding key and value to term.")
    error ->
      handle_recovery_error(error, __STACKTRACE__, "Could not recover stashed state.")
  end

  defp parse_state(stashed_state) do
    stashed_state
    |> Enum.map(fn {key, value} ->
      {key |> Base.decode64!() |> :erlang.binary_to_term([:safe]),
      value |> Base.decode64!() |> :erlang.binary_to_term([:safe])}
    end)
    |> Enum.into(%{})
  end

  defp handle_recovery_error(error, stacktrace, message) do
    err = Utils.error_message(message, error, stacktrace)
    Logger.error(err)

    {:error, err}
  end

  @impl true
  def reset_stash(socket) do
    LiveView.push_event(socket, "live-stash:reset", %{})
  end
end
