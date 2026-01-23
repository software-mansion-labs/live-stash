defmodule LiveStash.Server.Storage do
  @moduledoc false

  use GenServer

  @table_name :live_stash_server_storage

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      {:write_concurrency, true},
      {:decentralized_counters, true}
    ])

    {:ok, %{}}
  end

  @spec insert_state(id :: term(), state :: map()) :: :ok | {:error, any()}
  def insert_state(id, state) do
    :ets.insert(@table_name, {id, self(), System.os_time(), state})
    :ok
  rescue
    error ->
      {:error, error}
  end

  @spec put_state(id :: term(), key :: term(), value :: term()) :: :ok | {:error, any()}
  def put_state(id, key, value) do
    @table_name
    |> :ets.lookup(id)
    |> case do
      [{^id, _pid, _time, map_state}] ->
        new_map = Map.put(map_state, key, value)
        insert_state(id, new_map)

      [] ->
        insert_state(id, %{key => value})
    end
  rescue
    error ->
      {:error, error}
  end

  @spec change_owner(id :: term(), new_owner :: pid()) :: :ok | {:error, any()}
  def change_owner(id, new_owner) do
    :ets.update_element(@table_name, id, [{2, new_owner}])
    :ok
  rescue
    error ->
      {:error, error}
  end

  @spec bump_timestamp(id :: term()) :: :ok | {:error, any()}
  def bump_timestamp(id) do
    :ets.update_element(@table_name, id, [{3, System.os_time()}])
    :ok
  rescue
    error ->
      {:error, error}
  end

  @spec delete_state(id :: term()) :: :ok | {:error, any()}
  def delete_state(id) do
    :ets.delete(@table_name, id)
    :ok
  rescue
    error ->
      {:error, error}
  end

  @spec get_state(id :: term()) :: {:ok, map()} | {:error, any()}
  def get_state(id) do
    @table_name
    |> :ets.lookup(id)
    |> case do
      [{^id, _pid, _time, state}] -> {:ok, state}
      [] -> {:error, :not_found}
    end
  rescue
    error ->
      {:error, error}
  end
end
