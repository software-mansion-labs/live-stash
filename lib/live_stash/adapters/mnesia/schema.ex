defmodule LiveStash.Adapters.Mnesia.Schema do
  @moduledoc false

  use Amnesia

  defdatabase LiveStash.Adapters.Mnesia.Database do
    deftable State, [:id, :pid, :delete_at, :ttl, :state] do
      @type t :: %State{
              id: term(),
              pid: pid(),
              delete_at: integer(),
              ttl: integer(),
              state: map()
            }

      def new(id, state, opts) do
        ttl = Keyword.fetch!(opts, :ttl)

        %State{
          id: id,
          pid: self(),
          delete_at: System.os_time(:second) + ttl,
          ttl: ttl,
          state: state
        }
      end

      def create_table! do
        if Amnesia.Table.exists?(__MODULE__) do
          :ok
        else
          _ = Amnesia.Schema.create([node()])
          _ = Amnesia.start()

          try do
            database().create!(memory: [node()])
          rescue
            Amnesia.TableExistsError -> :ok
          end

          _ = database().wait(15_000)
          :ok
        end
      end

      def ensure_cluster_copies!(nodes) when is_list(nodes) do
        desired_nodes =
          nodes
          |> Enum.uniq()
          |> Enum.filter(&(&1 in [node() | Node.list()]))

        existing_nodes = :mnesia.table_info(__MODULE__, :ram_copies)

        desired_nodes
        |> Enum.reject(&(&1 in existing_nodes))
        |> Enum.each(fn target_node ->
          case add_copy(target_node, :memory) do
            :ok ->
              :ok

            {:error, {:already_exists, _}} ->
              :ok

            {:error, {:aborted, {:already_exists, _}}} ->
              :ok

            {:error, reason} ->
              raise "Could not add Mnesia table copy on #{inspect(target_node)}: #{inspect(reason)}"
          end
        end)

        :ok
      end

      def insert!(record) do
        write!(record)
        :ok
      end

      def put!(id, state, opts) do
        pid = self()
        record = new(id, state, opts)

        transaction_result =
          Amnesia.transaction do
            case read(id) do
              nil ->
                write(record)
                :ok

              %__MODULE__{pid: ^pid} ->
                write(record)
                :ok

              %__MODULE__{} ->
                Amnesia.abort(:conflict)
            end
          end

        case transaction_result do
          :ok ->
            :ok

          {:aborted, :conflict} ->
            msg = "State with id #{inspect(id)} already exists for another process"
            raise RuntimeError, msg

          {:aborted, reason} ->
            raise RuntimeError, "Mnesia transaction aborted: #{inspect(reason)}"
        end
      end

      def get_by_id!(id) do
        case read!(id) do
          nil -> :not_found
          %__MODULE__{state: state} -> {:ok, state}
        end
      end

      def delete_by_id!(id) do
        delete!(id)
        :ok
      end

      def expired_records(now) when is_integer(now) do
        stream!()
        |> Stream.filter(fn record -> record.delete_at < now end)
        |> Stream.map(fn record -> {record.id, record.pid, record.ttl} end)
      end

      def bump_delete_at!(id, time) when is_integer(time) do
        case read!(id) do
          nil ->
            :ok

          record ->
            %{record | delete_at: time}
            |> write!()

            :ok
        end
      end
    end
  end
end
