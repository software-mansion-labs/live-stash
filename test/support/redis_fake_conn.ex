defmodule LiveStash.TestRedisConn do
  @moduledoc false

  @behaviour :gen_statem
  require Logger

  @conn_name LiveStash.Adapters.Redis.Conn

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @conn_name)

    :gen_statem.start_link({:local, name}, __MODULE__, %{store: %{}, failures: %{}}, [])
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
        ref = Process.monitor(pid)
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
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

  defp handle_command(["SET", key, value, "EX", _exp], %{store: store} = state) do
    {"OK", %{state | store: Map.put(store, key, value)}}
  end

  defp handle_command(["GET", key], %{store: store} = state) do
    {Map.get(store, key), state}
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
end
