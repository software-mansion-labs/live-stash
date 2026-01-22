defmodule LiveStash.Client do
  @moduledoc """
  A client-side stash that persists data in the browser's memory.
  """

  @behaviour LiveStash.Stash

  @impl true
  def init(socket, opts) do
    dbg(opts)
    socket
  end
end
