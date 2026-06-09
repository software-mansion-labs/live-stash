defmodule LiveStash.Adapters.Mnesia.State do
  @moduledoc """
  A module that manages the state of LiveViews stored on the server. It uses Mnesia to store the state with in-memory copies and replication.

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
  Ensures the `State` table exists and is replicated to this node, independent of
  cluster boot order.

  Safe to call repeatedly: it joins any reachable peers
  into a shared schema, creates the table if no node has it yet, and ensures a
  local `ram_copies` replica. Concurrent calls from multiple nodes are tolerated
  because the underlying Mnesia schema operations are serialized cluster-wide and
  "already exists" results are treated as success.
  """
  @spec ensure_cluster_table!([node()]) :: :ok
  def ensure_cluster_table!(peers \\ Node.list()) do
    join_peers!(peers)
    ensure_table!()
    ensure_local_copy!()
    wait_for_table!()
  end

  @join_retries 5
  @join_retry_delay_ms 300

  defp join_peers!([]), do: :ok
  defp join_peers!(peers), do: join_peers!(peers, @join_retries)

  defp join_peers!(peers, attempts_left) do
    case Memento.add_nodes(peers) do
      {:ok, _added} ->
        peers
        |> Enum.reject(&(&1 in :mnesia.system_info(:db_nodes)))
        |> handle_unmerged(attempts_left)

      {:error, reason} ->
        raise RuntimeError, Utils.reason_message("Failed to join Mnesia cluster", reason)
    end
  end

  defp handle_unmerged([], _attempts_left), do: :ok

  # Retry every still-unmerged peer: Erlang distribution connects at VM start, so
  # a `:nodeup` can fire before the peer's Mnesia has even started. We can't tell
  # "not a Mnesia node" from "Mnesia not up yet" at a single instant, so we keep
  # retrying.
  defp handle_unmerged(unmerged, attempts_left) when attempts_left > 0 do
    Process.sleep(@join_retry_delay_ms)
    join_peers!(unmerged, attempts_left - 1)
  end

  defp handle_unmerged(unmerged, _attempts_left) do
    {running, non_mnesia} = Enum.split_with(unmerged, &mnesia_running?/1)
    warn_unmerged(running)
    log_non_mnesia(non_mnesia)
    :ok
  end

  defp warn_unmerged([]), do: :ok

  defp warn_unmerged(peers) do
    Logger.warning(
      Utils.reason_message(
        "Mnesia peers are running Mnesia but did not merge into the cluster",
        {:unmerged, peers}
      )
    )
  end

  defp log_non_mnesia([]), do: :ok

  defp log_non_mnesia(nodes) do
    Logger.debug(
      Utils.reason_message("Ignoring connected nodes not running Mnesia", {:no_mnesia, nodes})
    )
  end

  defp mnesia_running?(node) do
    :erpc.call(node, :mnesia, :system_info, [:is_running], 2_000) == :yes
  end

  defp ensure_table!() do
    __MODULE__
    |> Memento.Table.create(ram_copies: [node()])
    |> accept_already_exists!("Failed to set up Mnesia table")
  end

  defp ensure_local_copy!() do
    __MODULE__
    |> Memento.Table.create_copy(node(), :ram_copies)
    |> accept_already_exists!("Failed to create local Mnesia copy")
  end

  defp accept_already_exists!(:ok, _context), do: :ok
  defp accept_already_exists!({:error, {:already_exists, _}}, _context), do: :ok
  defp accept_already_exists!({:error, {:already_exists, _, _}}, _context), do: :ok

  defp accept_already_exists!({:error, reason}, context) do
    raise RuntimeError, Utils.reason_message(context, reason)
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
  Gets the state of a LiveView from the Mnesia table and re-inserts it with new delete_at and PID
  """
  @spec recover_and_insert!(id :: binary(), opts :: keyword()) :: {:ok, map()} | :not_found
  def recover_and_insert!(id, opts) do
    Memento.transaction!(fn ->
      case Memento.Query.read(__MODULE__, id) do
        nil ->
          :not_found

        %__MODULE__{state: recovered_state} ->
          record = new(id, recovered_state, opts)

          Memento.Query.write(record)

          {:ok, recovered_state}
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
