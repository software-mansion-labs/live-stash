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
    status = LiveView.get_connect_params(socket)["live-stash-state"]["status"]
    mounts = LiveView.get_connect_params(socket)["_mounts"]
    reconnected? = not is_nil(mounts) and mounts > 0 and status == "initialized"

    socket
    |> LiveView.put_private(:live_stash_mode, :client)
    |> LiveView.put_private(:live_stash_reconnected?, reconnected?)
    |> send_init_message()
  end

  @impl true
  def stash_assign(socket, key, value) do
    socket
    |> LiveView.push_event("live-stash:stash", %{key: key, value: value})
    |> Component.assign(key, value)
  end

  @impl true
  def recover_state(socket) do
    liveStashState = LiveView.get_connect_params(socket)["live-stash-state"]

    case liveStashState do
      %{"stashedState" => stashedState} ->
        parsedAssigns =
          stashedState
          |> Enum.map(fn {key, value} -> {String.to_existing_atom(key), value} end)
          |> Enum.into(%{})

        {:recovered, Component.assign(socket, parsedAssigns)}

      _ ->
        {:not_found, socket}
    end
  rescue
    error ->
      err = Utils.error_message("Could not recover state", error, __STACKTRACE__)
      Logger.error(err)

      {:error, socket}
  end

  defp send_init_message(socket) do
    LiveView.push_event(socket, "live-stash:init", %{
      status: "initialized"
    })
  end
end
