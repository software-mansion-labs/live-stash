defmodule LiveStash.Client do
  @moduledoc """
  A client-side stash that persists data in the browser's memory.
  """

  @behaviour LiveStash.Stash

  require Logger

  @impl true
  def init_stash(socket, _opts) do
    Logger.warning("[LiveStash] Client mode is not implemented yet")
    socket
  end

  @impl true
  def stash_assign(socket, _key, _value) do
    Logger.warning("[LiveStash] Client mode is not implemented yet")
    socket
  end

  @impl true
  def recover_state(socket) do
    Logger.warning("[LiveStash] Client mode is not implemented yet")
    socket
  end
end
