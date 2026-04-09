defmodule LiveStash.Adapters.Redis do
  @moduledoc """
  A server-side stash that persists data in Redis.
  """

  @behaviour LiveStash.Adapter

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias LiveStash.Adapters.Redis.Context
  alias LiveStash.Utils
  alias LiveStash.Adapters.Redis.Registry

  require Logger

  @conn_name __MODULE__.Conn
  @conn_options [name: @conn_name, sync_connect: false]

  @doc false
  @impl true
  def child_spec(opts \\ []) do
    redix_args = build_redix_args()

    children = [
      {Redix, redix_args},
      {LiveStash.Adapters.Redis.Cleaner, opts},
      {LiveStash.Adapters.Redis.Storage, opts}
    ]

    %{
      id: __MODULE__,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]},
      type: :supervisor
    }
  end

  defp build_redix_args() do
    uri_or_opts = Application.get_env(:live_stash, :redis, [])

    case uri_or_opts do
      uri when is_binary(uri) ->
        {uri, @conn_options}

      {uri, extra_opts} when is_binary(uri) and is_list(extra_opts) ->
        {uri, Keyword.merge(extra_opts, @conn_options)}

      config_opts when is_list(config_opts) ->
        Keyword.merge(config_opts, @conn_options)
    end
  end

  def command(cmd) do
    Redix.command(@conn_name, cmd)
  end

  @impl true
  def init_stash(socket, session, opts) do
    context = Context.new(socket, session, opts)
    socket = LiveView.put_private(socket, :live_stash_context, context)

    if not context.reconnected? do
      reset_stash(socket)
    end

    LiveView.push_event(socket, "live-stash:init-redis", %{
      stashId: context.id
    })
  end

  @impl true
  def stash(socket) do
    context = socket.private.live_stash_context

    keys = context.assigns
    assigns_to_stash = Map.take(socket.assigns, keys)
    new_fingerprint = Common.hash_term(assigns_to_stash)

    id = get_redis_key(socket)
    ttl = context.ttl
    serialized_assigns = :erlang.term_to_binary(assigns_to_stash)

    if new_fingerprint != context.fingerprint do
      case command(["SET", id, serialized_assigns, "EX", to_string(ttl)]) do
        {:ok, "OK"} ->
          Registry.put!(id, ttl: ttl)

          new_context = %{context | stash_fingerprint: new_fingerprint}

          socket
          |> LiveView.put_private(:live_stash_context, new_context)

        {:error, error} ->
          err = format_command_error_message("Failed to stash assigns", error)
          Logger.error(err)
          socket
      end
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
  def recover_state(%{private: %{live_stash_context: %{reconnected?: true}}} = socket) do
    id = get_redis_key(socket)

    case command(["GET", id]) do
      {:ok, nil} ->
        {:not_found, socket}

      {:ok, binary_state} when is_binary(binary_state) ->
        recovered_state = :erlang.binary_to_term(binary_state)
        {:recovered, Component.assign(socket, recovered_state)}

      {:error, error} ->
        err = format_command_error_message("Failed to recover state", error)
        Logger.error(err)
        {:error, socket}
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
    id = get_redis_key(socket)

    Registry.delete_by_id!(id)

    case command(["DEL", id]) do
      {:ok, _count} ->
        socket

      {:error, error} ->
        err = format_command_error_message("Failed to reset stash", error)
        Logger.error(err)
        socket
    end
  rescue
    error ->
      err = Utils.exception_message("Failed to reset stash", error, __STACKTRACE__)
      Logger.error(err)
      socket
  end

  defp get_redis_key(socket) do
    id = socket.private.live_stash_context.id
    secret = socket.private.live_stash_context.secret

    raw_key = id <> secret
    hashed_binary = :crypto.hash(:sha256, raw_key)

    "live_stash:" <> Base.encode64(hashed_binary, padding: false)
  end

  defp format_command_error_message(message, error) do
    case error do
      %Redix.Error{} = redis_error ->
        Utils.exception_message("#{message} - Redis error", redis_error)

      %Redix.ConnectionError{} = conn_error ->
        Utils.reason_message("#{message} - Redis connection error", conn_error)

      other ->
        Utils.reason_message(message, other)
    end
  end
end
