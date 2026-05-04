defmodule LiveStash.Adapters.Redis do
  @moduledoc """
  A server-side stash that persists data in Redis.

  See the [Redis Adapter Guide](redis.html) for usage and configuration details
  (source: `docs/redis.md`).
  """

  @behaviour LiveStash.Adapter

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias LiveStash.Adapters.Redis.Context
  alias LiveStash.Utils

  require Logger

  @conn_name __MODULE__.Conn
  @conn_options [name: @conn_name, sync_connect: false]

  @stash_script """
  local key = KEYS[1]
  local owner_id = ARGV[1]
  local payload = ARGV[2]
  local ttl = tonumber(ARGV[3])

  local existing_owner = redis.call('HGET', key, 'owner_id')

  if existing_owner and existing_owner ~= owner_id then
    return {err = 'Ownership mismatch'}
  end

  redis.call('HSET', key, 'owner_id', owner_id, 'payload', payload)
  redis.call('EXPIRE', key, ttl)

  return 'OK'
  """

  @recover_script """
  local key = KEYS[1]
  local new_owner_id = ARGV[1]

  local payload = redis.call('HGET', key, 'payload')
  if not payload then
    return nil
  end

  redis.call('HSET', key, 'owner_id', new_owner_id)
  return payload
  """

  @doc false
  @impl true
  def child_spec(_opts \\ []) do
    redix_args = build_redix_args()

    %{
      id: __MODULE__,
      start: {Redix, :start_link, [redix_args]}
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

      invalid ->
        msg =
          Utils.reason_message(
            "Invalid :live_stash, :redis configuration: #{inspect(invalid)}. " <>
              "Expected one of: a Redis URI string, a {uri, options} tuple, " <>
              "or a keyword list of Redix options.",
            :invalid
          )

        raise ArgumentError, msg
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

    ttl = context.ttl
    send_keep_alive(ttl)

    socket
    |> attach_keep_alive_hook()
    |> LiveView.push_event("live-stash:init-redis", %{
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
      redis_key = get_redis_key(socket)
      owner_id = inspect(self())
      payload = :erlang.term_to_binary(assigns_to_stash)
      ttl = context.ttl

      case eval_script(@stash_script, [redis_key], [owner_id, payload, ttl]) do
        {:ok, "OK"} ->
          new_context = %{context | stash_fingerprint: new_fingerprint}
          LiveView.put_private(socket, :live_stash_context, new_context)

        {:error, %Redix.Error{message: "Ownership mismatch"}} ->
          msg =
            Utils.reason_message(
              "Failed to stash assigns - stash already exists for another process",
              :conflict
            )

          raise RuntimeError, msg

        {:error, error} ->
          err = format_command_error_message("Failed to stash assigns", error)
          Logger.error(err)
          socket
      end
    else
      socket
    end
  end

  @impl true
  def recover_state(%{private: %{live_stash_context: %{reconnected?: true}}} = socket) do
    redis_key = get_redis_key(socket)
    new_owner_id = inspect(self())

    case eval_script(@recover_script, [redis_key], [new_owner_id]) do
      {:ok, nil} ->
        {:not_found, socket}

      {:ok, binary_state} when is_binary(binary_state) ->
        try do
          recovered_state = :erlang.binary_to_term(binary_state, [:safe])
          context = socket.private.live_stash_context
          fingerprint = Utils.hash_term(recovered_state)
          updated_context = %{context | stash_fingerprint: fingerprint}

          socket
          |> Component.assign(recovered_state)
          |> LiveView.put_private(:live_stash_context, updated_context)
          |> then(&{:recovered, &1})
        rescue
          error in ArgumentError ->
            err =
              Utils.exception_message(
                "Could not deserialize recovered state (invalid atoms)",
                error,
                __STACKTRACE__
              )

            Logger.error(err)
            {:error, socket}
        end

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
    redis_key = get_redis_key(socket)
    context = socket.private.live_stash_context
    updated_context = %{context | stash_fingerprint: nil}

    case command(["DEL", redis_key]) do
      {:ok, _count} ->
        LiveView.put_private(socket, :live_stash_context, updated_context)

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

  defp eval_script(script, keys, args) do
    num_keys = length(keys)

    normalized_args =
      Enum.map(args, fn
        arg when is_integer(arg) -> Integer.to_string(arg)
        arg -> arg
      end)

    cmd = ["EVAL", script, to_string(num_keys)] ++ keys ++ normalized_args

    command(cmd)
  end

  defp attach_keep_alive_hook(socket) do
    LiveView.attach_hook(socket, :live_stash_keep_alive, :handle_info, fn
      :live_stash_keep_alive, current_socket ->
        updated_socket = handle_keep_alive(current_socket)
        {:halt, updated_socket}

      _msg, current_socket ->
        {:cont, current_socket}
    end)
  end

  defp handle_keep_alive(socket) do
    context = socket.private.live_stash_context
    ttl = context.ttl
    redis_key = get_redis_key(socket)

    Task.start(fn ->
      case command(["EXPIRE", redis_key, to_string(ttl)]) do
        {:ok, _} ->
          :ok

        {:error, error} ->
          err =
            format_command_error_message("Failed to refresh stash for key #{redis_key}", error)

          Logger.error(err)
      end
    end)

    send_keep_alive(ttl)
    socket
  end

  defp send_keep_alive(ttl) do
    keep_alive_interval = max(div(ttl * 1_000, 2), 1_000)
    Process.send_after(self(), :live_stash_keep_alive, keep_alive_interval)
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
