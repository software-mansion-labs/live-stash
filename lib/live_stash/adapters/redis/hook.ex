defmodule LiveStash.Adapters.Redis.Hook do
  @moduledoc false

  alias Phoenix.LiveView
  alias LiveStash.Adapters.Redis.Helpers

  require Logger

  @hook_name :live_stash_keep_alive

  @doc """
  Schedules the first keep-alive tick and attaches the LiveView `:handle_info`
  hook that refreshes the TTL on every tick.

  The redis key is derived from the context on each tick so that it stays
  correct after `reset_stash/1` rotates the stash ID.
  """
  def attach(socket) do
    ttl = socket.private.live_stash_context.ttl
    send_keep_alive(ttl)

    LiveView.attach_hook(socket, @hook_name, :handle_info, &handle_keep_alive/2)
  end

  defp handle_keep_alive(@hook_name, socket) do
    context = socket.private.live_stash_context
    ttl = context.ttl
    redis_key = Helpers.redis_key(context.id, context.secret)

    Task.start(fn ->
      try do
        case Helpers.bump_ttl(redis_key, ttl) do
          :ok -> :ok
          {:error, err} -> Logger.error(err)
        end
      catch
        :exit, _ -> :ok
      end
    end)

    send_keep_alive(ttl)

    {:halt, socket}
  end

  defp handle_keep_alive(_msg, socket), do: {:cont, socket}

  defp send_keep_alive(ttl) do
    interval = div(ttl * 1_000, 2)
    Process.send_after(self(), @hook_name, interval)
  end
end
