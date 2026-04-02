defmodule LiveStash.Adapters.BrowserMemory do
  @moduledoc """
  A client-side stash that persists data in the browser's memory.

  See the [Browser Memory Adapter Guide](browser_memory.html) for usage and
  configuration details (source: `docs/browser_memory.md`).
  """

  @behaviour LiveStash.Adapter

  require Logger

  alias LiveStash.Utils
  alias LiveStash.Adapters.BrowserMemory.Serializer
  alias LiveStash.Adapters.BrowserMemory.Context

  alias Phoenix.LiveView
  alias Phoenix.Component

  @impl true
  def init_stash(socket, session, opts) do
    context = Context.new(socket, session, opts)

    socket = Phoenix.LiveView.put_private(socket, :live_stash_context, context)

    # If mounts is set to 0 we are on a new connection and stashed state is no longer valid
    if context.reconnected? do
      socket
    else
      socket
      |> LiveView.push_event("live-stash:init-browser-memory", %{})
    end
  end

  @impl true
  def stash_assigns(socket, keys) do
    context = socket.private.live_stash_context

    updated_context = %{context | key_set: MapSet.union(context.key_set, MapSet.new(keys))}

    socket = LiveView.put_private(socket, :live_stash_context, updated_context)

    serialized_assigns =
      Enum.reduce(keys, %{}, fn key, acc ->
        value = Map.fetch!(socket.assigns, key)

        {serialized_key, serialized_value} =
          Serializer.term_to_external(socket, key, value, get_settings(socket))

        Map.put(acc, serialized_key, serialized_value)
      end)

    payload = %{
      "assigns" => serialized_assigns,
      "keys" => Serializer.term_to_external(socket, keys, get_settings(socket))
    }

    LiveView.push_event(socket, "live-stash:stash-state", payload)
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
  def recover_state(%{private: %{live_stash_context: %Context{reconnected?: true}}} = socket) do
    case LiveView.get_connect_params(socket) do
      %{"liveStash" => %{"stashedState" => %{"assigns" => stashed_state, "keys" => stashed_keys}}}
      when is_map(stashed_state) ->
        case Serializer.external_to_term(
               socket,
               stashed_state,
               stashed_keys,
               get_settings(socket)
             ) do
          {:ok, {recovered_state, key_set}} ->
            context = socket.private.live_stash_context
            updated_context = %{context | key_set: key_set}

            socket
            |> Component.assign(recovered_state)
            |> LiveView.put_private(:live_stash_context, updated_context)
            |> then(&{:recovered, &1})

          {:error, msg} ->
            Logger.error(msg)

            socket
            |> LiveView.put_private(:live_stash_context, %{
              socket.private.live_stash_context
              | key_set: MapSet.new()
            })
            |> LiveView.push_event("live-stash:init-browser-memory", %{})
            |> then(&{:error, &1})
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

  def recover_state(socket), do: {:new, socket}

  @impl true
  def reset_stash(socket) do
    context = socket.private.live_stash_context
    updated_context = %{context | key_set: MapSet.new()}

    socket
    |> LiveView.push_event("live-stash:init-browser-memory", %{})
    |> LiveView.put_private(:live_stash_context, updated_context)
  end

  defp get_settings(socket) do
    %{
      ttl: socket.private.live_stash_context.ttl,
      secret: socket.private.live_stash_context.secret,
      security_mode: socket.private.live_stash_context.security_mode
    }
  end
end
