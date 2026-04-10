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
  alias LiveStash.Adapters.Common
  alias LiveStash.Utils

  alias Phoenix.LiveView

  @doc false
  @impl true
  def child_spec(opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc false
  def start_link(opts \\ []) do
    children = [
      {LiveStash.Adapters.ETS.Storage, opts},
      {LiveStash.Adapters.ETS.Cleaner, opts}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__.Supervisor)
  end

  @impl true
  def init_stash(socket, session, opts) do
    context = Context.new(socket, session, opts)

    socket = Phoenix.LiveView.put_private(socket, :live_stash_context, context)

    if not context.reconnected? do
      socket
      |> get_ets_id()
      |> State.delete_by_id!()
    end

    node_hint = NodeHint.create_node_hint(socket)

    LiveView.push_event(socket, "live-stash:init-ets", %{
      node: node_hint,
      stashId: context.id
    })
  end

  defp get_ets_id(socket) do
    id = socket.private.live_stash_context.id
    secret = socket.private.live_stash_context.secret

    raw_key = id <> secret
    hashed_binary = :crypto.hash(:sha256, raw_key)

    Base.encode64(hashed_binary, padding: false)
  end

  @impl true
  def stash(socket) do
    context = socket.private.live_stash_context
    keys = context.assigns
    assigns_to_stash = Map.take(socket.assigns, keys)
    new_fingerprint = Common.hash_term(assigns_to_stash)

    if new_fingerprint != context.stash_fingerprint do
      State.put!(get_ets_id(socket), assigns_to_stash, get_opts(socket))

      new_context = %{context | stash_fingerprint: new_fingerprint}

      socket
      |> LiveView.put_private(:live_stash_context, new_context)
    else
      socket
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
        fingerprint = Common.hash_term(recovered_state)
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
      err = Utils.exception_message("Could not recover state", error, __STACKTRACE__)
      Logger.error(err)

      {:error, socket}
  end

  def recover_state(socket), do: {:new, socket}

  @impl true
  def reset_stash(socket) do
    context = socket.private.live_stash_context
    updated_context = %{context | stash_fingerprint: nil}

    socket
    |> get_ets_id()
    |> State.delete_by_id!()

    LiveView.put_private(socket, :live_stash_context, updated_context)
  rescue
    error ->
      err = Utils.exception_message("Could not reset stash", error, __STACKTRACE__)
      Logger.error(err)

      socket
  end

  defp get_opts(socket) do
    [ttl: socket.private.live_stash_context.ttl]
  end
end
