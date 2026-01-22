defmodule LiveStash.Server do
  @moduledoc """
  A server-side stash that persists data in the server's memory.
  """

  @behaviour LiveStash.Stash

  @impl true
  def init(socket, opts) do
    dbg(opts)
    socket
  end
end
