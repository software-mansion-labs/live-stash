defmodule LiveStash.Stash do
  @moduledoc """
  A stash is a module that manages the storage and retrieval of data.
  """

  alias Phoenix.LiveView.Socket

  @callback init_stash(socket :: Socket.t(), opts :: Keyword.t()) :: Socket.t()
  @callback stash_assign(socket :: Socket.t(), key :: atom(), value :: term()) :: Socket.t()
  @callback recover_state(socket :: Socket.t()) ::
              {:recovered, socket :: Socket.t()}
              | {:not_found, socket :: Socket.t()}
              | {:new, socket :: Socket.t()}
              | {:error, socket :: Socket.t()}
end
