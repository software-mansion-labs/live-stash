defmodule LiveStash.Client do
  @moduledoc """
  A client-side stash that persists data in the browser's memory.
  """

  @behaviour LiveStash.Stash

  require Logger

  alias LiveStash.Utils

  alias Phoenix.LiveView
  alias Phoenix.Component

  @impl true
  def init_stash(socket, _opts) do
    mounts = LiveView.get_connect_params(socket)["_mounts"]
    reconnected? = not is_nil(mounts) and mounts > 0

    if not reconnected? do
      LiveView.push_event(socket, "live-stash:reset", %{})
    end

    socket
    |> LiveView.put_private(:live_stash_mode, :client)
    |> LiveView.put_private(:live_stash_reconnected?, reconnected?)
  end

  @impl true
  def stash_assign(socket, key, value) do
    socket
    |> LiveView.push_event("live-stash:stash", %{key: key, value: value})
    |> Component.assign(key, value)
  end

  @impl true
  def recover_state(socket) do
    case LiveView.get_connect_params(socket) do
      %{"stashedState" => stashed_state} ->
        parsed_assigns =
          stashed_state
          |> Enum.map(fn {key, value} -> {String.to_existing_atom(key), value} end)
          |> Enum.into(%{})

        {:recovered, Component.assign(socket, parsed_assigns)}

      _ ->
        {:not_found, socket}
    end
  rescue
    error ->
      err = Utils.error_message("Could not recover state", error, __STACKTRACE__)
      Logger.error(err)

      {:error, socket}
  end
end
