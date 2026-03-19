defmodule LiveStash.Adapter do
  @moduledoc """
  A LiveStash adapter is a module that manages the storage and retrieval of data.
  """

  alias Phoenix.LiveView.Socket

  @type recovery_status :: :recovered | :not_found | :new | :error

  @callback init_stash(socket :: Socket.t(), session :: Keyword.t(), opts :: Keyword.t()) ::
              Socket.t()
  @callback stash_assigns(socket :: Socket.t(), keys :: [atom()]) :: Socket.t()
  @callback recover_state(socket :: Socket.t()) :: {recovery_status(), Socket.t()}
  @callback reset_stash(socket :: Socket.t()) :: Socket.t()
  @callback child_spec(args :: any()) :: Supervisor.child_spec()

  @optional_callbacks child_spec: 1
end
