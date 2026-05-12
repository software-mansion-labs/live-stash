defmodule LiveStash.Adapters.Redis do
  @moduledoc """
  A server-side stash that persists data in Redis.

  See the [Redis Adapter Guide](redis.html) for usage and configuration details
  (source: `docs/redis.md`).
  """

  @compile {:no_warn_undefined, [Redix]}

  @behaviour LiveStash.Adapter

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias LiveStash.Adapters.Redis.{Helpers, Hook}
  alias LiveStash.Utils
  alias LiveStash.Adapters.Common

  require Logger

  @doc false
  @impl true
  def child_spec(_opts \\ []) do
    unless Code.ensure_loaded?(Redix) do
      msg =
        Utils.reason_message(
          """
          To use the Redis adapter, please add the following to your mix.exs dependencies:
          {:redix, "~> 1.1"}
          {:castore, ">= 0.0.0"} # If you need SSL
          """,
          :missing_dependency
        )

      raise RuntimeError, msg
    end

    Supervisor.child_spec({Redix, Helpers.redix_args!()}, id: __MODULE__)
  end

  @impl true
  def init_stash(socket, session, opts) do
    {socket, context} = Common.init_context(socket, session, opts, __MODULE__)

    if not context.reconnected? do
      delete_stash(get_redis_key(socket))
    end

    socket
    |> Hook.attach()
    |> LiveView.push_event("live-stash:init-redis", %{stashId: context.id})
  end

  @impl true
  def stash(socket) do
    context = socket.private.live_stash_context
    keys = context.stored_keys
    assigns_to_stash = Map.take(socket.assigns, keys)
    new_fingerprint = Utils.hash_term(assigns_to_stash)

    with true <- new_fingerprint != context.stash_fingerprint,
         redis_key = get_redis_key(socket),
         owner_id = :erlang.term_to_binary(self()),
         payload = :erlang.term_to_binary(assigns_to_stash),
         :ok <- Helpers.save(redis_key, owner_id, payload, context.ttl) do
      new_context = %{context | stash_fingerprint: new_fingerprint}
      LiveView.put_private(socket, :live_stash_context, new_context)
    else
      false ->
        socket

      {:error, :ownership_mismatch} ->
        msg =
          Utils.reason_message(
            "Failed to stash assigns - stash already exists for another process",
            :conflict
          )

        Logger.error(msg)
        socket

      {:error, err} ->
        Logger.error(err)
        socket
    end
  end

  @impl true
  def recover_state(%{private: %{live_stash_context: %{reconnected?: true, ttl: ttl}}} = socket) do
    redis_key = get_redis_key(socket)
    new_owner_id = :erlang.term_to_binary(self())

    case Helpers.recover(redis_key, new_owner_id, ttl) do
      {:ok, :not_found} ->
        {:not_found, socket}

      {:ok, binary_state} ->
        apply_recovered_state(socket, binary_state)

      {:error, err} ->
        Logger.error(err)
        {:error, socket}
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
    context = socket.private.live_stash_context

    case delete_stash(get_redis_key(socket)) do
      :ok ->
        updated_context = %{context | stash_fingerprint: nil}
        LiveView.put_private(socket, :live_stash_context, updated_context)

      {:error, _} ->
        new_id = Uniq.UUID.uuid4()
        updated_context = %{context | id: new_id, stash_fingerprint: nil}

        socket
        |> LiveView.put_private(:live_stash_context, updated_context)
        |> LiveView.push_event("live-stash:init-redis", %{stashId: new_id})
    end
  rescue
    error ->
      err = Utils.exception_message("Failed to reset stash", error, __STACKTRACE__)
      Logger.error(err)
      socket
  end

  defp apply_recovered_state(socket, binary_state) do
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
          "Failed to deserialize recovered state (invalid atoms)",
          error,
          __STACKTRACE__
        )

      Logger.error(err)
      {:error, socket}
  end

  defp delete_stash(redis_key) do
    case Helpers.delete(redis_key) do
      :ok ->
        :ok

      {:error, err} = error ->
        Logger.error(err)
        error
    end
  end

  defp get_redis_key(socket) do
    context = socket.private.live_stash_context
    Helpers.redis_key(context.id, context.secret)
  end
end
