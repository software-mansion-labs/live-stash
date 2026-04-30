defmodule LiveStash.Component do
  @moduledoc """
  LiveStash support for `Phoenix.LiveComponent`.

  A LiveComponent has no `connect_params` of its own and its `mount/1` runs
  with an empty socket — neither the parent-supplied `id` nor the user's
  assigns are available there. The earliest moment a component has a stable
  identity is its first `update/2` call, so recovery is gated on that.

  ## Usage

      defmodule MyCounterComponent do
        use Phoenix.LiveComponent
        use LiveStash.Component, stored_keys: [:count]

        def mount(socket) do
          # Defaults. If `:count` is recovered later, this value is overridden.
          {:ok, assign(socket, :count, 0)}
        end

        # Optional. Runs once after recovery, before first render.
        def mount_stashed(socket) do
          if socket.private[:live_stash_recovered?] do
            socket
          else
            kick_off_initial_load(socket)
          end
        end

        # Optional. If defined, must call super first.
        def update(assigns, socket) do
          {:ok, socket} = super(assigns, socket)
          {:ok, react_to_assigns(socket, assigns)}
        end

        def handle_event("inc", _, socket) do
          socket
          |> assign(:count, socket.assigns.count + 1)
          |> LiveStash.Component.stash()
          |> then(&{:noreply, &1})
        end
      end

  ## Lifecycle

  On the first `update/2`:

  1. Macro-generated wrapper reads recovered state for `{__MODULE__, assigns.id}`
     from the parent LiveView's process dictionary (populated by the root's
     adapter during `LiveStash.recover_state/1`).
  2. Recovered keys are merged into `socket.assigns`. The entry is deleted from
     the process dictionary.
  3. `socket.private[:live_stash_recovered?]` is set to `true` (recovered) or
     `false` (no state found).
  4. `mount_stashed/1` runs if defined.
  5. Parent `assigns` are merged via the default `update/2` body.

  On subsequent `update/2` calls, the flag is already set and the macro skips
  recovery entirely.

  ## The `:live_stash_recovered?` flag

  Stored in `socket.private`, never in `socket.assigns` (would otherwise be
  shipped to the client and pollute change tracking). Three states:

    * `nil` — recovery hasn't run yet.
    * `true` — recovery ran and a slice was found.
    * `false` — recovery ran and nothing was found.

  Read from your own `update/2` or `mount_stashed/1` if you need to branch on
  recovery status.
  """

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias Phoenix.LiveView.Socket

  alias LiveStash.Utils

  @doc false
  defmacro __using__(opts) do
    quote do
      @live_stash_component_opts unquote(opts)

      def update(assigns, socket) do
        socket =
          LiveStash.Component.__before_update__(
            socket,
            assigns,
            @live_stash_component_opts,
            __MODULE__
          )

        {:ok, Phoenix.Component.assign(socket, assigns)}
      end

      defoverridable update: 2
    end
  end

  @doc """
  Recovers stashed state on the first `update/2` call and runs `mount_stashed/1`.

  Internal — invoked by the macro-generated `update/2`. Idempotent: the
  `:live_stash_recovered?` private flag gates this so subsequent calls return
  the socket untouched.
  """
  @spec __before_update__(Socket.t(), map(), keyword(), module()) :: Socket.t()
  def __before_update__(socket, assigns, opts, module) do
    if socket.private[:live_stash_recovered?] != nil do
      socket
    else
      id = fetch_id!(assigns, module)
      key = {module, id}

      socket =
        socket
        |> LiveView.put_private(:live_stash_component_module, module)
        |> LiveView.put_private(:live_stash_component_opts, opts)

      stash_map = Process.get(:live_stash_components, %{})

      socket =
        case Map.pop(stash_map, key) do
          {nil, _rest} ->
            LiveView.put_private(socket, :live_stash_recovered?, false)

          {recovered_assigns, rest} ->
            Process.put(:live_stash_components, rest)

            socket
            |> Component.assign(recovered_assigns)
            |> LiveView.put_private(:live_stash_recovered?, true)
        end

      if function_exported?(module, :mount_stashed, 1) do
        module.mount_stashed(socket)
      else
        socket
      end
    end
  end

  @doc """
  Stashes the component's `stored_keys` by sending an upstream message to the
  root LiveView, which is responsible for persisting the merged blob.

  Use this from a component the same way you'd use `LiveStash.stash/1` from a
  LiveView — typically after a state-changing event:

      def handle_event("inc", _, socket) do
        socket
        |> assign(:count, socket.assigns.count + 1)
        |> LiveStash.Component.stash()
        |> then(&{:noreply, &1})
      end
  """
  @spec stash(Socket.t()) :: Socket.t()
  def stash(socket) do
    module = fetch_private!(socket, :live_stash_component_module)
    opts = fetch_private!(socket, :live_stash_component_opts)
    id = fetch_id!(socket.assigns, module)
    keys = Keyword.fetch!(opts, :stored_keys)

    assigns_to_stash = Map.take(socket.assigns, keys)
    send(socket.root_pid, {:live_stash_component_stash, {module, id}, assigns_to_stash})

    socket
  end

  defp fetch_private!(socket, key) do
    case socket.private[key] do
      nil ->
        msg =
          Utils.reason_message(
            "LiveStash.Component.stash/1 called outside of a LiveStash component context. " <>
              "Missing private key: #{inspect(key)}. Did you `use LiveStash.Component` in the component module?",
            :invalid
          )

        raise ArgumentError, msg

      value ->
        value
    end
  end

  defp fetch_id!(%{id: id}, _module) when is_binary(id) or is_integer(id), do: to_string(id)

  defp fetch_id!(_assigns, module) do
    msg =
      Utils.reason_message(
        "LiveStash.Component requires an `id` assign to be passed in the component's assigns. " <>
          "No `id` found for #{inspect(module)}. Please ensure the component is rendered with an `id`: " <>
          "<.live_component module={#{inspect(module)}} id=\"...\" />",
        :invalid
      )

    raise ArgumentError, msg
  end
end
