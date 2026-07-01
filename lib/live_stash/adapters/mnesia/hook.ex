defmodule LiveStash.Adapters.Mnesia.Hook do
  @moduledoc false

  alias LiveStash.Adapters.Mnesia.{Helpers, State}
  alias Phoenix.LiveView
  alias LiveStash.Utils

  @compile {:no_warn_undefined, [LiveStash.Adapters.Mnesia.State]}

  require Logger

  @hook_name :live_stash_keep_alive

  @doc """
  Schedules the first keep-alive tick and attaches the LiveView `:handle_info`
  hook that refreshes the TTL on every tick.

  The Mnesia id is derived from the context on each tick.
  """
  def attach(socket) do
    ttl = socket.private.live_stash_context.ttl
    send_keep_alive(ttl)

    LiveView.attach_hook(socket, @hook_name, :handle_info, &handle_keep_alive/2)
  end

  defp handle_keep_alive(@hook_name, socket) do
    context = socket.private.live_stash_context
    ttl = context.ttl
    id = Helpers.mnesia_id(context.id, context.secret)

    try do
      State.bump_delete_at!(id, ttl)
    rescue
      _ ->
        msg = Utils.reason_message("Failed to bump TTL for Mnesia stash with id #{id}", :error)
        Logger.error(msg)
    end

    send_keep_alive(ttl)

    {:halt, socket}
  end

  defp handle_keep_alive(_msg, socket), do: {:cont, socket}

  defp send_keep_alive(ttl) do
    interval = div(ttl * 1_000, 4)
    Process.send_after(self(), @hook_name, interval)
  end
end
