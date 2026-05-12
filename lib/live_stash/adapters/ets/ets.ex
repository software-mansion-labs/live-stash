defmodule LiveStash.Adapters.ETS do
  @moduledoc """
  A server-side stash that persists data in the server's memory.

  See the [ETS Adapter Guide](ets.html) for usage and configuration details
  (source: `docs/ets.md`).
  """

  @behaviour LiveStash.Adapter

  require Logger

  alias Phoenix.Component

  alias LiveStash.Adapters.ETS.NodeHint
  alias LiveStash.Adapters.ETS.State
  alias LiveStash.Adapters.ETS.StateFinder
  alias LiveStash.Adapters.ETS.Context
  alias LiveStash.Utils
  alias LiveStash.Adapters.Common

  alias Phoenix.LiveView

  @doc false
  @impl true
  def child_spec(opts \\ []) do
    children = [
      {LiveStash.Adapters.ETS.Storage, opts},
      {LiveStash.Adapters.ETS.Cleaner, opts}
    ]

    %{
      id: __MODULE__,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]},
      type: :supervisor
    }
  end

  @impl true
  def init_stash(socket, session, opts) do
    socket = Common.init_context(socket, session, opts, __MODULE__)
    context = socket.private.live_stash_context

    socket =
      if not context.reconnected? do
        try do
          socket
          |> get_ets_id()
          |> State.delete_by_id!()
        rescue
          error ->
            err =
              Utils.exception_message(
                "Failed to clear existing stash on new connection",
                error,
                __STACKTRACE__
              )

            Logger.error(err)
        end

        Common.rotate_id(socket)
      else
        socket
      end

    node_hint = NodeHint.create_node_hint(socket)

    LiveView.push_event(socket, "live-stash:init-ets", %{
      node: node_hint,
      stashId: socket.private.live_stash_context.id
    })
  end

  @impl true
  def stash(socket) do
    context = socket.private.live_stash_context
    keys = context.stored_keys
    assigns_to_stash = Map.take(socket.assigns, keys)
    new_fingerprint = Utils.hash_term(assigns_to_stash)

    if new_fingerprint != context.stash_fingerprint do
      State.put!(get_ets_id(socket), assigns_to_stash, get_opts(socket))

      new_context = %{context | stash_fingerprint: new_fingerprint}

      socket
      |> LiveView.put_private(:live_stash_context, new_context)
    else
      socket
    end
  end

  @impl true
  def recover_state(%{private: %{live_stash_context: %Context{reconnected?: true}}} = socket) do
    id = get_ets_id(socket)
    node_hint = socket.private.live_stash_context.node_hint

    case StateFinder.get_from_cluster(id, node_hint) do
      {:ok, recovered_state} ->
        id
        |> State.new(recovered_state, get_opts(socket))
        |> State.insert!()

        context = socket.private.live_stash_context
        fingerprint = Utils.hash_term(recovered_state)
        updated_context = %{context | stash_fingerprint: fingerprint}

        socket
        |> Component.assign(recovered_state)
        |> LiveView.put_private(:live_stash_context, updated_context)
        |> then(&{:recovered, &1})

      :not_found ->
        {:not_found, socket}
    end
  rescue
    error ->
      err = Utils.exception_message("Failed to recover state", error, __STACKTRACE__)
      Logger.error(err)

      {:error, socket}
  end

  def recover_state(socket), do: {:new, socket}

  @impl true
  def reset_stash(socket) do
    try do
      socket
      |> get_ets_id()
      |> State.delete_by_id!()
    rescue
      error ->
        err =
          Utils.exception_message(
            "Failed to delete stash during reset. Rotating ID as fallback.",
            error,
            __STACKTRACE__
          )

        Logger.error(err)

        socket
        |> Common.rotate_id()
        |> Common.clear_fingerprint()

        LiveView.push_event(socket, "live-stash:init-ets", %{
          node: socket.private.live_stash_context.node_hint,
          stashId: socket.private.live_stash_context.id
        })
    end
  end

  defp get_ets_id(socket) do
    id = socket.private.live_stash_context.id
    secret = socket.private.live_stash_context.secret

    raw_key = id <> secret
    hashed_binary = :crypto.hash(:sha256, raw_key)

    Base.encode64(hashed_binary, padding: false)
  end

  defp get_opts(socket) do
    [ttl: socket.private.live_stash_context.ttl]
  end
end
