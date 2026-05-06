defmodule LiveStash.Adapters.Redis.Hook do
  @moduledoc false

  alias Phoenix.LiveView
  alias LiveStash.Adapters.Redis.Helpers

  require Logger

  @hook_name :live_stash_keep_alive
  @msg :live_stash_keep_alive

  @doc """
  Schedules the first keep-alive tick and attaches the LiveView `:handle_info`
  hook that refreshes the TTL on `redis_key` on every tick.
  """
  def attach(socket, redis_key) do
    ttl = socket.private.live_stash_context.ttl
    send_keep_alive(redis_key, ttl)

    LiveView.attach_hook(socket, @hook_name, :handle_info, &handle_keep_alive/2)
  end

  defp handle_keep_alive({@msg, redis_key}, socket) do
    ttl = socket.private.live_stash_context.ttl

    Task.start(fn ->
      case Helpers.bump_ttl(redis_key, ttl) do
        :ok -> :ok
        {:error, err} -> Logger.error(err)
      end
    end)

    send_keep_alive(redis_key, ttl)

    {:halt, socket}
  end

  defp handle_keep_alive(_msg, socket), do: {:cont, socket}

  defp send_keep_alive(redis_key, ttl) do
    interval = div(ttl * 1_000, 2)
    Process.send_after(self(), {@msg, redis_key}, interval)
  end
end
