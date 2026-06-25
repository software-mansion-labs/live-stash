defmodule TestingWeb.Performance.Config do
  @moduledoc false

  @default_ttl 60
  @default_cleanup_ms 30_000

  @spec ttl() :: pos_integer()
  def ttl do
    read_int("LIVE_STASH_TTL", @default_ttl)
  end

  @spec ets_cleanup_interval_ms() :: pos_integer()
  def ets_cleanup_interval_ms do
    read_int("LIVE_STASH_ETS_CLEANUP_INTERVAL_MS", @default_cleanup_ms)
  end

  @spec mnesia_cleanup_interval_ms() :: pos_integer()
  def mnesia_cleanup_interval_ms do
    read_int("LIVE_STASH_MNESIA_CLEANUP_INTERVAL_MS", @default_cleanup_ms)
  end

  defp read_int(env, default) do
    case System.get_env(env) do
      nil -> default
      val -> String.to_integer(val)
    end
  end
end
