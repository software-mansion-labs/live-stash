defmodule LiveStash.Adapter do
  @moduledoc """
  A LiveStash adapter is a module that manages the storage and retrieval of data.
  """

  alias Phoenix.LiveView.Socket

  @doc false
  def default, do: LiveStash.Adapters.BrowserMemory

  @type recovery_status :: :recovered | :not_found | :new | :error

  @doc """
  Initializes the stash state for the given LiveView socket. It receives the connection session and any options passed during configuration. Returns the updated socket.
  """
  @callback init_stash(socket :: Socket.t(), session :: Keyword.t(), opts :: Keyword.t()) ::
              Socket.t()
  @doc """
  Persists the specified assigns keys for the given LiveView socket. Returns the updated socket.
  """
  @callback stash_assigns(socket :: Socket.t(), keys :: [atom()]) :: Socket.t()
  @doc """
  Retrieves the stored state and attempts to restore it to the socket. It must return a tuple containing the recovery status and the updated socket.
  """
  @callback recover_state(socket :: Socket.t()) :: {recovery_status(), Socket.t()}
  @doc """
  Clears the currently stored state for the socket. Returns the updated socket.
  """
  @callback reset_stash(socket :: Socket.t()) :: Socket.t()
  @doc """
  Creates a child specification for the adapter's supervisor.
  """
  @callback child_spec(args :: any()) :: Supervisor.child_spec()

  @optional_callbacks child_spec: 1
end
