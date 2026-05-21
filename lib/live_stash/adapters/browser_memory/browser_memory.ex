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
  alias LiveStash.Adapters.Common

  alias Phoenix.LiveView
  alias Phoenix.Component

  @impl true
  def init_stash(socket, session, opts) do
    socket = Common.init_context(socket, session, opts, __MODULE__)
    context = socket.private.live_stash_context

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
    new_fingerprint = Utils.hash_term(assigns_to_stash)

    if new_fingerprint != context.stash_fingerprint do
      wrapped = %{version: context.version, assigns: assigns_to_stash}

      serialized_assigns =
        Serializer.encode_token(socket, wrapped, get_settings(socket))

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
    context = socket.private.live_stash_context

    with %{"liveStash" => %{"stashedState" => stashed_state}} when is_binary(stashed_state) <-
           LiveView.get_connect_params(socket),
         {:ok, decoded} <-
           Serializer.decode_token(socket, stashed_state, get_settings(socket)),
         {:ok, recovered_state} <- unwrap_payload(decoded, context.version) do
      fingerprint = Utils.hash_term(recovered_state)
      updated_context = %{context | stash_fingerprint: fingerprint}

      socket
      |> Component.assign(recovered_state)
      |> LiveView.put_private(:live_stash_context, updated_context)
      |> then(&{:recovered, &1})
    else
      {:error, :version_mismatch} ->
        msg =
          Utils.reason_message(
            "Rejecting stashed state due to version mismatch.",
            :version_mismatch
          )

        Logger.info(msg)

        socket
        |> LiveView.push_event("live-stash:init-browser-memory", %{})
        |> then(&{:error, &1})

      {:error, reason} ->
        msg =
          Utils.reason_message(
            "Failed to recover stashed state from token.",
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
          "Failed to recover stashed state due to an unexpected error.",
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

  defp unwrap_payload(%{version: v, assigns: assigns}, v), do: {:ok, assigns}
  defp unwrap_payload(_, _), do: {:error, :version_mismatch}

  defp get_settings(socket) do
    %{
      ttl: socket.private.live_stash_context.ttl,
      secret: socket.private.live_stash_context.secret,
      security_mode: socket.private.live_stash_context.security_mode
    }
  end
end
