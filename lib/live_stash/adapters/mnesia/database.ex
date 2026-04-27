defmodule LiveStash.Adapters.Mnesia.Database do
  @moduledoc false

  alias LiveStash.Adapters.Mnesia.Schema.LiveStash.Adapters.Mnesia.Database, as: Impl

  defdelegate create!(copying \\ []), to: Impl
  defdelegate create(copying \\ []), to: Impl
  defdelegate destroy!(), to: Impl
  defdelegate destroy(), to: Impl
  defdelegate wait(timeout \\ :infinity), to: Impl
  defdelegate metadata(), to: Impl

  defmodule State do
    @moduledoc false

    alias LiveStash.Adapters.Mnesia.Schema.LiveStash.Adapters.Mnesia.Database.State, as: Impl

    defdelegate new(id, state, opts), to: Impl
    defdelegate create_table!(), to: Impl
    defdelegate insert!(record), to: Impl
    defdelegate put!(id, state, opts), to: Impl
    defdelegate get_by_id!(id), to: Impl
    defdelegate delete_by_id!(id), to: Impl
    defdelegate expired_records(now), to: Impl
    defdelegate bump_delete_at!(id, time), to: Impl
    defdelegate ensure_cluster_copies!(nodes), to: Impl
  end
end
