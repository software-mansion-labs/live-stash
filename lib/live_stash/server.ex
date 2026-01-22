defmodule LiveStash.Server do
  @moduledoc """
  A server-side stash that persists data in the server's memory.
  """

  @behaviour LiveStash.Stash

  alias Phoenix.LiveView

  @impl true
  def init(socket, opts) do
    ttl = Keyword.fetch!(opts, :ttl)
    stashed_assigns = Keyword.fetch!(opts, :stashed_assigns)
    mounts = LiveView.get_connect_params(socket)["_mounts"]

    socket
    |> LiveView.put_private(:live_stash_mode, :server)
    |> LiveView.put_private(:live_stash_ttl, ttl)
    |> LiveView.put_private(:live_stash_stashed_assigns, stashed_assigns)
    |> LiveView.put_private(:live_stash_reconnected?, not is_nil(mounts) and mounts > 0)
  end
end
