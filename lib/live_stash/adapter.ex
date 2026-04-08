defmodule LiveStash.Adapter do
  @moduledoc """
  Behaviour for storage backends used by `LiveStash`.

  An adapter is responsible for persisting and restoring selected LiveView
  assigns for a specific socket identity. `LiveStash` delegates all storage
  operations to the adapter chosen during initialization.
  """

  alias Phoenix.LiveView.Socket

  @doc false
  def default, do: LiveStash.Adapters.BrowserMemory

  @type recovery_status :: :recovered | :not_found | :new | :error

  @doc """
  Initializes adapter state for the given socket.

  Called during LiveView mount through `LiveStash.on_mount/4`.
  Receives session data and adapter options and must return an updated socket.
  """
  @callback init_stash(socket :: Socket.t(), session :: Keyword.t(), opts :: Keyword.t()) ::
              Socket.t()

  @doc """
  Persists declared assign keys for the given socket.

  The keys are atoms that reference entries in `socket.assigns`.
  Returns an updated socket.
  """
  @callback stash(socket :: Socket.t()) :: Socket.t()

  @doc """
  Attempts to restore previously persisted state to the socket.

  Must return `{status, socket}` where `status` is one of
  `t:recovery_status/0`.
  """
  @callback recover_state(socket :: Socket.t()) :: {recovery_status(), Socket.t()}
  @doc """
  Removes stored state associated with the socket and returns it.
  """
  @callback reset_stash(socket :: Socket.t()) :: Socket.t()
  @doc """
  Returns a child specification when the adapter needs supervision.
  """
  @callback child_spec(args :: any()) :: Supervisor.child_spec()

  @optional_callbacks child_spec: 1
end
