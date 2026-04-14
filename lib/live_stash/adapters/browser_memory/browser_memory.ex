defmodule LiveStash.Adapters.BrowserMemory do
  @moduledoc """
  A client-side stash that persists data in the browser's memory.

  See the [Browser Memory Adapter Guide](browser_memory.html) for usage and
  configuration details (source: `docs/browser_memory.md`).
  """

  @behaviour LiveStash.Adapter

  require Logger

  alias LiveStash.Utils
  alias LiveStash.Adapters.Common
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
  def stash(socket) do
    context = socket.private.live_stash_context
    keys = context.stored_keys
    assigns_to_stash = Map.take(socket.assigns, keys)
    new_fingerprint = Common.hash_term(assigns_to_stash)

    if new_fingerprint != context.stash_fingerprint do
      serialized_assigns =
        Serializer.encode_token(socket, assigns_to_stash, get_settings(socket))

      payload = %{
        "assigns" => serialized_assigns
      }

      new_context = %{context | stash_fingerprint: new_fingerprint}

      socket
      |> LiveView.put_private(:live_stash_context, new_context)
      |> LiveView.push_event("live-stash:stash-state", payload)
    else
      socket
    end
  end

  @impl true
  def recover_state(%{private: %{live_stash_context: %Context{reconnected?: true}}} = socket) do
    with %{"liveStash" => %{"stashedState" => stashed_state}} when is_binary(stashed_state) <-
           LiveView.get_connect_params(socket),
         {:ok, recovered_state} <-
           Serializer.decode_token(socket, stashed_state, get_settings(socket)) do
      context = socket.private.live_stash_context
      fingerprint = Common.hash_term(recovered_state)
      updated_context = %{context | stash_fingerprint: fingerprint}

      socket
      |> Component.assign(recovered_state)
      |> LiveView.put_private(:live_stash_context, updated_context)
      |> then(&{:recovered, &1})
    else
      {:error, reason} ->
        msg =
          Utils.reason_message(
            "Failed to decode stashed state from token.",
            reason
          )

        Logger.warning(msg)

        socket
        |> LiveView.push_event("live-stash:init-browser-memory", %{})
        |> then(&{:error, &1})

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
    updated_context = %{context | stash_fingerprint: nil}

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
