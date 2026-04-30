defmodule LiveStash do
  @moduledoc """
  Main public API for stashing and recovering `Phoenix.LiveView` assigns.

  `LiveStash` helps preserve selected server-side assigns across reconnects.
  You explicitly choose which assigns to persist and when to persist them.

  This module:

  - integrates with `on_mount` via `use LiveStash`
  - initializes the selected adapter
  - delegates persistence and recovery operations to that adapter

  ## Quick start

  Add `use LiveStash` to your LiveView:

      defmodule MyAppWeb.CounterLive do
        use MyAppWeb, :live_view
        use LiveStash, stored_keys: [:count]
      end

  Stash assigns after state-changing events:

      def handle_event("increment", _, socket) do
        socket
        |> assign(:count, socket.assigns.count + 1)
        |> LiveStash.stash()
        |> then(&{:noreply, &1})
      end

  Recover stashed state in `mount/3`:

      def mount(_params, _session, socket) do
        socket
        |> LiveStash.recover_state()
        |> case do
          {:recovered, recovered_socket} ->
            # socket with previously stashed assigns is recovered
            recovered_socket

          {_, socket} ->
            # could not recover assigns, proceed with standard setup using returned socket
            # ...
        end
        |> then(&{:ok, &1})
      end

  ## Recovery statuses

  `recover_state/1` returns `{status, socket}` where `status` is one of:

  - `:new` - fresh LiveView process, with no previously stashed state
  - `:recovered` - state was found and applied
  - `:not_found` - state was not found for this LiveView
  - `:error` - adapter failed to recover state

  ## Adapter selection

  The default adapter is `LiveStash.Adapters.BrowserMemory`.
  You can override it per LiveView:

      use LiveStash, adapter: LiveStash.Adapters.ETS

  Adapters used by your app must also be enabled in config:

      config :live_stash,
        adapters: [LiveStash.Adapters.BrowserMemory, LiveStash.Adapters.ETS]
  """

  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView
  alias LiveStash.Utils

  require Logger

  @type recovery_status :: :recovered | :not_found | :new | :error

  @doc """
  Injects LiveStash support into a `Phoenix.LiveView`. This macro expands to:

      on_mount({LiveStash, opts})

  so that LiveStash can initialize stash handling during the LiveView `mount/3`
  lifecycle.

  ## Options

  The `opts` are forwarded to `LiveStash.on_mount/4` and ultimately to the
  configured adapter. Most adapters use `:adapter` to select the persistence
  backend:

      use LiveStash, adapter: LiveStash.Adapters.ETS

  Note: adapters must also be enabled in `config :live_stash, :adapters`.

  ## Example

      defmodule MyAppWeb.CounterLive do
        use MyAppWeb, :live_view
        use LiveStash, adapter: LiveStash.Adapters.BrowserMemory
      end
  """
  defmacro __using__(opts) do
    quote do
      on_mount({LiveStash, unquote(opts)})
    end
  end

  @doc """
  LiveView `on_mount` callback used by `use LiveStash`.

  It initializes stash handling for the current socket and continues the mount
  lifecycle.
  """
  def on_mount(opts, _params, session, socket) do
    socket =
      socket
      |> init_stash(session, opts)
      |> attach_component_stash_hook()

    {:cont, socket}
  end

  @doc false
  # Attaches a handle_info hook that receives stash messages from
  # LiveStash-aware components rendered under this LiveView. The hook updates
  # the in-memory components buffer in socket.private and triggers an adapter
  # stash so the merged blob (root assigns + components map) is persisted.
  def attach_component_stash_hook(socket) do
    LiveView.attach_hook(
      socket,
      :live_stash_component_stash,
      :handle_info,
      &handle_component_stash/2
    )
  end

  defp handle_component_stash(
         {:live_stash_component_stash, key, assigns_to_stash},
         socket
       ) do
    buffer = socket.private[:live_stash_components_buffer] || %{}
    new_buffer = Map.put(buffer, key, assigns_to_stash)

    socket =
      socket
      |> LiveView.put_private(:live_stash_components_buffer, new_buffer)
      |> stash()

    {:halt, socket}
  end

  defp handle_component_stash(_msg, socket), do: {:cont, socket}

  @doc """
  Populates the process dictionary with recovered component state.

  Called by adapters during `recover_state/1` so that LiveStash-aware
  `Phoenix.LiveComponent`s can read their slice on first `update/2` (see
  `LiveStash.Component`). The map is keyed by `{component_module, id}`.
  """
  @spec put_recovered_components(map()) :: :ok
  def put_recovered_components(components_map) when is_map(components_map) do
    Process.put(:live_stash_components, components_map)
    :ok
  end

  @doc """
  Returns the components buffer accumulated from component stash messages.

  Adapters use this during `stash/1` to merge component state into the blob
  alongside the LiveView's own stored assigns.
  """
  @spec get_components_buffer(Socket.t()) :: map()
  def get_components_buffer(socket) do
    socket.private[:live_stash_components_buffer] || %{}
  end

  @doc """
  Initializes stash support for a socket using the configured adapter.

  This function is called from `on_mount/4`. In normal usage, prefer
  `use LiveStash` and do not call this function directly.

  It validates that the selected adapter is active in
  `config :live_stash, :adapters`.
  """
  @spec init_stash(socket :: Socket.t(), session :: Keyword.t(), opts :: Keyword.t()) ::
          Socket.t()
  def init_stash(socket, session, opts \\ []) do
    {adapter, opts} = Keyword.pop(opts, :adapter, LiveStash.Adapter.default())

    active_adapters = Application.get_env(:live_stash, :adapters, [LiveStash.Adapter.default()])

    if adapter not in active_adapters do
      msg =
        Utils.reason_message(
          "The adapter #{inspect(adapter)} is not active. Please add it to the :adapters list in your :live_stash config.",
          :invalid
        )

      raise ArgumentError, msg
    end

    socket
    |> LiveView.put_private(:live_stash_adapter, adapter)
    |> adapter.init_stash(session, opts)
  end

  @doc """
  Stashes assigns from `socket.assigns` declared at the module level.

  ## Examples
      use LiveStash, stored_keys: [:count, :username] # assigns are declared at the module level

      def handle_event("increment", _, socket) do
        socket
        |> assign(:count, socket.assigns.count + 1)
        |> LiveStash.stash()
        |> then(&{:noreply, &1})
      end
  """
  @spec stash(socket :: Socket.t()) :: Socket.t()
  def stash(socket) do
    socket
    |> get_adapter()
    |> apply(:stash, [socket])
  end

  @doc """
  Recovers previously stashed state and returns `{status, socket}`.

  This function is typically called in `mount/3`. Recovery does not clear the
  stored state; use `reset_stash/1` when you want to remove it explicitly.

  ## Examples
      def mount(_params, _session, socket) do
        socket
        |> LiveStash.recover_state()
        |> case do
          {:recovered, recovered_socket} ->
            recovered_socket

          {_, socket} ->
            start_new_game(socket)
        end
        |> then(&{:ok, &1})
      end
  """
  @spec recover_state(socket :: Socket.t()) :: {recovery_status(), Socket.t()}
  def recover_state(socket) do
    socket
    |> get_adapter()
    |> apply(:recover_state, [socket])
  end

  @doc """
  Clears stashed state for the current LiveView socket.

  ## Examples
      def handle_event("restart_game", _params, socket) do
        socket
        |> LiveStash.reset_stash()
        |> start_new_game()
        |> then(&{:noreply, &1})
      end
  """
  @spec reset_stash(socket :: Socket.t()) :: Socket.t()
  def reset_stash(socket) do
    socket
    |> get_adapter()
    |> apply(:reset_stash, [socket])
  end

  defp get_adapter(%{private: %{live_stash_adapter: adapter}}), do: adapter

  defp get_adapter(_) do
    msg =
      Utils.reason_message(
        "LiveStash has not been initialized, please use on_mount/1 to initialize it",
        :error
      )

    raise ArgumentError, msg
  end
end
