defmodule LiveStash.Adapters.Mnesia.State do
  @moduledoc """
  A module that manages the state of LiveViews stored on the server. It uses Mnesia to store the state.
  Mnesia replication is used, therefore the first approach is to connect to other nodes and create a copy of the table.

  The state is stored in the following format:
  - id: the id of the LiveView
  - pid: the pid of the LiveView
  - delete_at: the timestamp when the state should be deleted
  - state: the state of the LiveView
  """

  use Memento.Table,
    attributes: [:id, :pid, :delete_at, :state],
    type: :set

  require Logger
  alias LiveStash.Utils

  # `Memento.transaction/1`'s spec claims it always returns `{:ok, _} | {:error, _}`,
  # but in reality returns :ok. The `:ok ->` branch in `put!/3` is therefore reachable.
  @dialyzer {:no_match, put!: 3}

  @batch_size Application.compile_env(:live_stash, :mnesia_cleanup_batch_size, 100)

  @type t :: %__MODULE__{
          id: term(),
          pid: pid(),
          delete_at: integer(),
          state: map()
        }

  @doc """
  Creates a new state record for a LiveView.
  """
  @spec new(id :: binary(), state :: map(), opts :: keyword()) :: t()
  def new(id, state, opts) do
    ttl = Keyword.fetch!(opts, :ttl)

    %__MODULE__{
      id: id,
      pid: self(),
      delete_at: System.os_time(:second) + ttl,
      state: state
    }
  end

  @doc """
  Sets up the Mnesia table for storing LiveView states.
  If other nodes are already running, it creates a copy of the table on this node.
  Otherwise, it creates the table on this node as the first node in the cluster.
  """
  @spec setup_cluster_state!() :: :ok
  def setup_cluster_state!() do
    ensure_table_created!()
    wait_for_table!()
  end

  defp ensure_table_created!() do
    Node.list()
    |> init_table()
    |> handle_create_result!()
  end

  defp init_table([]) do
    Memento.Table.create(__MODULE__, ram_copies: [node()])
  end

  defp init_table(nodes) do
    case Memento.add_nodes(nodes) do
      {:ok, []} ->
        Logger.warning(
          Utils.reason_message(
            "Could not reach any Mnesia peer",
            {:requested_nodes, nodes}
          )
        )

        Memento.Table.create_copy(__MODULE__, node(), :ram_copies)

      {:ok, connected} ->
        missing = nodes -- connected

        if missing != [] do
          Logger.warning(
            Utils.message(
              "Mnesia joined #{inspect(connected)} of requested peers. Could not reach #{inspect(missing)}"
            )
          )
        end

        Memento.Table.create_copy(__MODULE__, node(), :ram_copies)

      {:error, reason} ->
        {:error, {:add_nodes_failed, reason}}
    end
  end

  defp handle_create_result!(:ok), do: :ok
  defp handle_create_result!({:error, {:already_exists, _}}), do: :ok
  defp handle_create_result!({:error, {:already_exists, _, _}}), do: :ok

  defp handle_create_result!({:error, {:add_nodes_failed, reason}}) do
    raise RuntimeError, Utils.reason_message("Failed to join Mnesia cluster", reason)
  end

  defp handle_create_result!({:error, reason}) do
    raise RuntimeError, Utils.reason_message("Failed to set up Mnesia table", reason)
  end

  defp wait_for_table!() do
    case Memento.Table.wait([__MODULE__], 15_000) do
      :ok ->
        :ok

      {:timeout, bad} ->
        raise RuntimeError,
              Utils.reason_message("Mnesia table did not become ready", {:timeout, bad})

      {:error, reason} ->
        raise RuntimeError, Utils.reason_message("Mnesia table wait failed", reason)
    end
  end

  @doc """
  Inserts a new state record for a LiveView into the Mnesia table.
  """
  @spec insert!(record :: t()) :: :ok
  def insert!(record) do
    Memento.transaction!(fn ->
      Memento.Query.write(record)
    end)

    :ok
  end

  @doc """
  Puts a new state map into the state of a LiveView or creates a new state record if it doesn't exist.
  Allows update only to the process that owns the state record (matching pid), otherwise raises an error.
  """
  @spec put!(id :: binary(), state :: map(), opts :: keyword()) :: :ok
  def put!(id, state, opts) do
    pid = self()
    record = new(id, state, opts)

    transaction_result =
      Memento.transaction(fn ->
        case Memento.Query.read(__MODULE__, id) do
          nil ->
            Memento.Query.write(record)
            :ok

          %__MODULE__{pid: ^pid} ->
            Memento.Query.write(record)
            :ok

          %__MODULE__{} ->
            Memento.Transaction.abort(:conflict)
        end
      end)

    case transaction_result do
      :ok ->
        :ok

      {:ok, _result} ->
        :ok

      {:error, reason} ->
        msg = Utils.reason_message("Mnesia transaction aborted", reason)
        raise RuntimeError, msg
    end
  end

  @doc """
  Gets the state of a LiveView from the Mnesia table.
  """
  @spec get_by_id!(id :: binary()) :: {:ok, map()} | :not_found
  def get_by_id!(id) do
    Memento.transaction!(fn ->
      case Memento.Query.read(__MODULE__, id) do
        nil -> :not_found
        %__MODULE__{state: state} -> {:ok, state}
      end
    end)
  end

  @doc """
  Deletes the state of a LiveView from the Mnesia table.
  """
  @spec delete_by_id!(id :: binary()) :: :ok
  def delete_by_id!(id) do
    Memento.transaction!(fn ->
      Memento.Query.delete(__MODULE__, id)
    end)

    :ok
  end

  @doc """
  Refreshes the `delete_at` of a record to `now + ttl`. No-op if the record
  does not exist.
  """
  @spec bump_delete_at!(id :: binary(), ttl :: integer()) :: :ok
  def bump_delete_at!(id, ttl) when is_integer(ttl) do
    Memento.transaction!(fn ->
      case Memento.Query.read(__MODULE__, id) do
        nil ->
          :ok

        record ->
          Memento.Query.write(%{record | delete_at: System.os_time(:second) + ttl})
          :ok
      end
    end)
  end

  @doc """
  Deletes every record whose `delete_at` is strictly less than `now` in batches.
  """
  @spec delete_expired!(now :: integer(), batch_size :: pos_integer()) :: integer()
  def delete_expired!(now, batch_size \\ @batch_size) when is_integer(now) do
    deleted_in_batch =
      Memento.transaction!(fn ->
        guard = {:<, :delete_at, now}

        records = Memento.Query.select(__MODULE__, guard, limit: batch_size)

        Enum.each(records, &Memento.Query.delete_record/1)

        length(records)
      end)

    if deleted_in_batch == batch_size do
      deleted_in_batch + delete_expired!(now, batch_size)
    else
      deleted_in_batch
    end
  end
end
