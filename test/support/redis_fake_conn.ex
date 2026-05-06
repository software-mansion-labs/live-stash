defmodule LiveStash.TestRedisConn do
  @moduledoc false

  @behaviour :gen_statem
  require Logger

  @conn_name LiveStash.Adapters.Redis.Conn

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @conn_name)

    initial_state = %{store: %{}, failures: %{}, scripts: %{}}
    :gen_statem.start_link({:local, name}, __MODULE__, initial_state, [])
  end

  def fail_next(command, reason \\ :simulated_error) when is_binary(command) do
    case Process.whereis(@conn_name) do
      nil ->
        {:error, :not_started}

      pid ->
        _ =
          :sys.replace_state(pid, fn
            {state_name, state} -> {state_name, put_in(state, [:failures, command], reason)}
            state -> put_in(state, [:failures, command], reason)
          end)

        :ok
    end
  end

  def stop do
    case Process.whereis(@conn_name) do
      nil ->
        :ok

      pid ->
        try do
          :gen_statem.stop(pid)
        catch
          :exit, _reason -> :ok
        end
    end
  end

  def snapshot do
    case Process.whereis(@conn_name) do
      nil ->
        %{store: %{}}

      pid ->
        case :sys.get_state(pid) do
          {_, state} -> state
          state -> state
        end
    end
  end

  @impl true
  def callback_mode, do: :state_functions

  @impl true
  def init(state), do: {:ok, :connected, state}

  def connected(:cast, {:pipeline, [command], from, _timeout}, state) do
    {reply, new_state} = handle_command(command, state)

    response =
      case reply do
        {:error, reason} -> {:error, reason}
        _ -> {:ok, [reply]}
      end

    send(elem(from, 0), {elem(from, 1), response})
    {:keep_state, new_state}
  end

  def connected(:cast, _message, state), do: {:keep_state, state}
  def connected(_event_type, _event_content, state), do: {:keep_state, state}

  defp handle_command([command | _rest], %{failures: failures} = state)
       when is_map_key(failures, command) do
    {reason, updated_failures} = Map.pop(failures, command)
    {{:error, reason}, %{state | failures: updated_failures}}
  end

  defp handle_command(["EVAL", script | rest], %{scripts: scripts} = state) do
    hash = :crypto.hash(:sha, script) |> Base.encode16(case: :lower)
    state = %{state | scripts: Map.put(scripts, hash, script)}
    eval(rest, state)
  end

  defp handle_command(["EVALSHA", hash | rest], %{scripts: scripts} = state) do
    if Map.has_key?(scripts, hash) do
      eval(rest, state)
    else
      {{:error,
        %{__struct__: Redix.Error, message: "NOSCRIPT No matching script. Please use EVAL."}},
       state}
    end
  end

  defp handle_command(["HSET", key, field1, val1, field2, val2], %{store: store} = state) do
    new_hash = %{field1 => val1, field2 => val2}
    updated_store = Map.update(store, key, new_hash, &Map.merge(&1, new_hash))
    {"OK", %{state | store: updated_store}}
  end

  defp handle_command(["HSET", key, field, val], %{store: store} = state) do
    new_hash = %{field => val}
    updated_store = Map.update(store, key, new_hash, &Map.merge(&1, new_hash))
    {"OK", %{state | store: updated_store}}
  end

  defp handle_command(["HGET", key, field], %{store: store} = state) do
    {get_in(store, [key, field]), state}
  end

  defp handle_command(["EXPIRE", _key, _ttl], state) do
    {1, state}
  end

  defp handle_command(["DEL", key], %{store: store} = state) do
    {removed_value, updated_store} = Map.pop(store, key)
    deleted_count = if is_nil(removed_value), do: 0, else: 1
    {deleted_count, %{state | store: updated_store}}
  end

  defp handle_command(other, state) do
    Logger.error("Unexpected Redis command in test: #{inspect(other)}")
    {{:error, :unexpected_command}, state}
  end

  defp eval(["1", key, owner_id, payload, _ttl], %{store: store} = state) do
    existing_owner = get_in(store, [key, "owner_id"])

    if not is_nil(existing_owner) and existing_owner != owner_id do
      {{:error, %{__struct__: Redix.Error, message: "Ownership mismatch"}}, state}
    else
      new_hash = %{"owner_id" => owner_id, "payload" => payload}
      updated_store = Map.update(store, key, new_hash, &Map.merge(&1, new_hash))

      {"OK", %{state | store: updated_store}}
    end
  end

  defp eval(["1", key, new_owner_id, _ttl], %{store: store} = state) do
    payload = get_in(store, [key, "payload"])

    if is_nil(payload) do
      {nil, state}
    else
      updated_store = Map.update!(store, key, &Map.put(&1, "owner_id", new_owner_id))
      {payload, %{state | store: updated_store}}
    end
  end
end
