defmodule LiveStash.Client do
  @moduledoc """
  A client-side stash that persists data in the browser's memory.
  """

  @behaviour LiveStash.Stash

  require Logger

  alias LiveStash.Utils
  alias LiveStash.Serializer

  alias Phoenix.LiveView
  alias Phoenix.Component

  @impl true
  def init_stash(socket, _session, _opts) do
    reconnected? = socket.private.live_stash.reconnected?

    # If mounts is set to 0 we are on a new connection and stashed state is no longer valid
    if reconnected? do
      socket
    else
      socket
      |> LiveView.push_event("live-stash:reset-state", %{})
      |> LiveView.put_private(:live_stash_keys, MapSet.new())
    end
  end

  @impl true
  def stash_assigns(socket, keys) do
    existing_keys = socket.private[:live_stash_keys]

    socket =
      LiveView.put_private(
        socket,
        :live_stash_keys,
        MapSet.union(existing_keys, MapSet.new(keys))
      )

    serialized_assigns =
      Enum.reduce(keys, %{}, fn key, acc ->
        value = Map.fetch!(socket.assigns, key)

        {serialized_key, serialized_value} =
          Serializer.term_to_external(socket, key, value, get_settings(socket))

        Map.put(acc, serialized_key, serialized_value)
      end)

    payload =
      %{
        assigns: serialized_assigns,
        keys: Serializer.term_to_external(socket, keys, get_settings(socket))
      }

    Phoenix.LiveView.push_event(socket, "live-stash:stash-state", payload)
  rescue
    e in KeyError ->
      msg =
        Utils.reason_message(
          "Failed to stash assigns. Key #{inspect(e.key)} is missing from socket.assigns.",
          :missing
        )

      reraise RuntimeError, msg, __STACKTRACE__
  end

  @impl true
  def recover_state(socket) do
    case LiveView.get_connect_params(socket) do
      %{"stashedState" => %{"assigns" => stashed_state, "keys" => stashed_keys}}
      when is_map(stashed_state) ->
        case Serializer.external_to_term(
               socket,
               stashed_state,
               stashed_keys,
               get_settings(socket)
             ) do
          {:ok, {recovered_state, key_set}} ->
            socket
            |> Component.assign(recovered_state)
            |> LiveView.put_private(:live_stash_keys, key_set)
            |> then(&{:recovered, &1})

          {:error, msg} ->
            Logger.error(msg)
            {:error, socket}
        end

      _ ->
        {:not_found, socket}
    end
  rescue
    error ->
      msg =
        Utils.exception_message(
          "Could not recover stashed state due to an unexpected error.",
          error,
          __STACKTRACE__
        )

      Logger.error(msg)

      {:error, socket}
  end

  @impl true
  def reset_stash(socket) do
    LiveView.push_event(socket, "live-stash:reset-state", %{})
    |> LiveView.put_private(:live_stash_keys, MapSet.new())
  end

  defp get_settings(socket) do
    %{
      ttl: socket.private.live_stash.ttl,
      secret: socket.private.live_stash.secret,
      security_mode: socket.private.live_stash.security_mode
    }
  end
end
