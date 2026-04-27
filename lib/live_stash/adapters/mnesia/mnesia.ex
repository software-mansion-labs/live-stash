defmodule LiveStash.Adapters.Mnesia do
  @moduledoc """
  A server-side stash that persists data in Mnesia.

  The adapter is replication-only: it configures native Mnesia table copies on
  connected nodes and relies on Mnesia replication.
  """

  @behaviour LiveStash.Adapter

  require Logger

  alias LiveStash.Adapters.Mnesia.Context
  alias LiveStash.Adapters.Mnesia.Database.State
  alias LiveStash.Utils

  alias Phoenix.Component
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
      {LiveStash.Adapters.Mnesia.Storage, opts},
      {LiveStash.Adapters.Mnesia.Cleaner, opts}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__.Supervisor)
  end

  @impl true
  def init_stash(socket, session, opts) do
    context = Context.new(socket, session, opts)

    socket = Phoenix.LiveView.put_private(socket, :live_stash_context, context)

    State.ensure_cluster_copies!([node() | Node.list()])

    if not context.reconnected? do
      get_mnesia_id(socket)
      |> State.delete_by_id!()
    end

    LiveView.push_event(socket, "live-stash:init-mnesia", %{
      stashId: context.id
    })
  end

  @impl true
  def stash(socket) do
    context = socket.private.live_stash_context
    keys = context.stored_keys
    assigns_to_stash = Map.take(socket.assigns, keys)
    new_fingerprint = Utils.hash_term(assigns_to_stash)

    if new_fingerprint != context.stash_fingerprint do
      State.put!(get_mnesia_id(socket), assigns_to_stash, get_opts(socket))

      new_context = %{context | stash_fingerprint: new_fingerprint}

      socket
      |> LiveView.put_private(:live_stash_context, new_context)
    else
      socket
    end
  end

  @impl true
  def recover_state(%{private: %{live_stash_context: %Context{reconnected?: true}}} = socket) do
    id = get_mnesia_id(socket)

    try do
      case State.get_by_id!(id) do
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
        err = Utils.exception_message("Could not recover state", error, __STACKTRACE__)
        Logger.error(err)

        {:error, socket}
    end
  end

  def recover_state(socket), do: {:new, socket}

  @impl true
  def reset_stash(socket) do
    context = socket.private.live_stash_context
    updated_context = %{context | stash_fingerprint: nil}

    try do
      get_mnesia_id(socket)
      |> State.delete_by_id!()

      LiveView.put_private(socket, :live_stash_context, updated_context)
    rescue
      error ->
        err = Utils.exception_message("Could not reset stash", error, __STACKTRACE__)
        Logger.error(err)

        socket
    end
  end

  defp get_mnesia_id(socket) do
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
