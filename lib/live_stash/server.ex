defmodule LiveStash.Server do
  @moduledoc """
  A server-side stash that persists data in the server's memory.
  """

  @behaviour LiveStash.Stash

  alias Phoenix.Component

  alias LiveStash.Server.NodeHint
  alias LiveStash.Server.State
  alias LiveStash.Server.StateFinder
  alias LiveStash.Utils

  alias Phoenix.LiveView

  require Logger

  @impl true
  def init_stash(socket, _session, _opts) do
    reconnected? = socket.private.live_stash.reconnected?

    id = fetch_stash_id(socket) || UUID.uuid4()
    socket = Phoenix.LiveView.put_private(socket, :live_stash_id, id)

    if not reconnected? do
      socket
      |> get_ets_id()
      |> State.delete_by_id!()
    end

    node_hint = NodeHint.create_node_hint(socket)
    LiveView.push_event(socket, "live-stash:init-server", %{node: node_hint, stashId: id})
  end

  defp fetch_stash_id(socket) do
    case Phoenix.LiveView.get_connect_params(socket) do
      %{"stashId" => id} when is_binary(id) ->
        id

      _ ->
        nil
    end
  end

  defp get_ets_id(socket) do
    id = socket.private.live_stash_id
    secret = socket.private.live_stash.secret

    raw_key = id <> secret
    hashed_binary = :crypto.hash(:sha256, raw_key)

    Base.encode64(hashed_binary, padding: false)
  end

  @impl true
  def stash_assigns(socket, keys) do
    state =
      Enum.reduce(keys, %{}, fn key, acc ->
        value = Map.fetch!(socket.assigns, key)
        Map.put(acc, key, value)
      end)

    State.put!(get_ets_id(socket), state, get_opts(socket))

    socket
  rescue
    e in KeyError ->
      msg =
        Utils.reason_message(
          "Failed to stash assigns. Key #{inspect(e.key)} is missing from socket.assigns.",
          :missing
        )

      reraise RuntimeError, msg, __STACKTRACE__
  end

  @impl true
  def recover_state(socket) do
    id = get_ets_id(socket)
    node_hint = socket.private.live_stash.node_hint

    case StateFinder.get_from_cluster(id, node_hint) do
      {:ok, recovered_state} ->
        id
        |> State.new(recovered_state, get_opts(socket))
        |> State.insert!()

        {:recovered, Component.assign(socket, recovered_state)}

      :not_found ->
        {:not_found, socket}
    end
  rescue
    error ->
      err = Utils.exception_message("Could not recover state", error, __STACKTRACE__)
      Logger.error(err)

      {:error, socket}
  end

  @impl true
  def reset_stash(socket) do
    socket
    |> get_ets_id()
    |> State.delete_by_id!()

    socket
  rescue
    error ->
      err = Utils.exception_message("Could not reset stash", error, __STACKTRACE__)
      Logger.error(err)

      socket
  end

  defp get_opts(socket) do
    [ttl: socket.private.live_stash.ttl]
  end
end
