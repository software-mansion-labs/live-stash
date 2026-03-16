defmodule LiveStash.Stash do
  @moduledoc """
  A stash is a module that manages the storage and retrieval of data.
  """

  alias Phoenix.LiveView.Socket

  @type recovery_status :: :recovered | :not_found | :new | :error

  @callback init_stash(socket :: Socket.t(), session :: map(), opts :: Keyword.t()) :: Socket.t()
  @callback stash(socket :: Socket.t(), key :: atom() | number() | binary(), value :: term()) ::
              Socket.t()
  @callback recover_state(socket :: Socket.t()) ::
              {recovery_status(), Socket.t()} | {recovery_status(), map()} | {:error, String.t()}
  @callback reset_stash(socket :: Socket.t()) :: Socket.t()
end
