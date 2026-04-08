defmodule LiveStash.Adapters.ETS.State do
  @moduledoc """
  A module that manages the state of LiveViews stored on the server. It uses ETS to store the state.

  The state is stored in the following format:
  - id: the id of the LiveView
  - pid: the pid of the LiveView
  - delete_at: the timestamp when the state should be deleted
  - ttl: the time to live of the state
  - state: the state of the LiveView
  """

  require Record

  @table_name Application.compile_env(:live_stash, :ets_table_name, :live_stash_server_storage)
  @batch_size Application.compile_env(:live_stash, :ets_cleanup_batch_size, 100)

  Record.defrecord(:state, [:id, :pid, :delete_at, :ttl, :state])

  @type t ::
          record(:state,
            id: term(),
            pid: pid(),
            delete_at: integer(),
            ttl: integer(),
            state: map()
          )

  @typep continuation :: tuple() | :"$end_of_table"

  @doc """
  Creates the ETS table for storing the state of LiveViews.
  Table name is configurable via the `:ets_table_name` config.
  """
  @spec create_table!() :: :ets.table()
  def create_table!() do
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      {:keypos, 2},
      {:write_concurrency, true},
      {:decentralized_counters, true}
    ])
  end

  @doc """
  Creates a new state record for a LiveView.
  """
  @spec new(id :: term(), state :: map(), opts :: Keyword.t()) :: t()
  def new(id, state, opts) do
    ttl = Keyword.fetch!(opts, :ttl)

    state(
      id: id,
      pid: self(),
      delete_at: System.os_time(:millisecond) + ttl,
      ttl: ttl,
      state: state
    )
  end

  @doc """
  Inserts a new state record for a LiveView into the ETS table.
  """
  @spec insert!(record :: tuple()) :: :ok
  def insert!(record) do
    :ets.insert(@table_name, record)
    :ok
  end

  @doc """
  Gets the state of a LiveView from the ETS table.
  """
  @spec get_by_id!(id :: term()) :: {:ok, map()} | :not_found
  def get_by_id!(id) do
    @table_name
    |> :ets.lookup(id)
    |> case do
      [{:state, ^id, _pid, _delete_at, _ttl, state}] -> {:ok, state}
      [] -> :not_found
    end
  end

  @doc """
  Deletes the state of a LiveView from the ETS table.
  """
  @spec delete_by_id!(id :: term()) :: :ok
  def delete_by_id!(id) do
    :ets.delete(@table_name, id)
    :ok
  end

  @doc """
  Pops the state of a LiveView from the ETS table, returning it and deleting the record.
  """
  @spec pop_by_id!(id :: term()) :: :not_found | {:ok, map()}
  def pop_by_id!(id) do
    @table_name
    |> :ets.take(id)
    |> case do
      [{:state, ^id, _pid, _delete_at, _ttl, state}] -> {:ok, state}
      [] -> :not_found
    end
  end

  @doc """
  Gets a batch of state records from the ETS table.
  """
  @spec get_batch!(now :: integer()) ::
          {[{term(), pid(), integer()}], continuation()} | :"$end_of_table"
  def get_batch!(now) when is_integer(now) do
    spec = [
      {
        # Pattern: {:state, id, pid, delete_at, ttl, _state}
        {:state, :"$1", :"$2", :"$3", :"$4", :_},
        # Guard: delete_at < now
        [{:<, :"$3", now}],
        # Return: {id, pid, ttl}
        [{{:"$1", :"$2", :"$4"}}]
      }
    ]

    :ets.select(@table_name, spec, @batch_size)
  end

  @doc """
  Gets the next batch of state records from the ETS table.
  """
  @spec get_next_batch!(continuation :: continuation()) ::
          {[{term(), pid(), integer()}], continuation()} | :"$end_of_table"
  def get_next_batch!(:"$end_of_table"), do: :"$end_of_table"
  def get_next_batch!(continuation), do: :ets.select(continuation)

  @doc """
  Bumps the delete_at time of a state record in the ETS table.
  """
  @spec bump_delete_at!(id :: term(), time :: integer()) :: :ok
  def bump_delete_at!(id, time) when is_integer(time) do
    :ets.update_element(@table_name, id, {4, time})
    :ok
  end
end
