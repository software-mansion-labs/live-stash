defmodule LiveStash.Stash do
  @moduledoc """
  A stash is a module that manages the storage and retrieval of data.
  """

  alias Phoenix.LiveView.Socket

  @callback init(socket :: Socket.t(), opts :: Keyword.t()) :: Socket.t()
end
