defmodule LiveStash.Server.NodeHint do
  @moduledoc """
  Handles encoding and sending the current node to the client as a hint for state recovery,
  and decrypting the node from connect params on reconnect.
  """

  require Logger

  alias Phoenix.LiveView
  alias LiveStash.Utils

  @doc """
  Pushes the current node (encrypted) to the client via a LiveView event so the client
  can store it as a node hint for later reconnection and state recovery.
  """
  @spec save_node_hint(socket :: LiveView.Socket.t()) :: LiveView.Socket.t()
  def save_node_hint(socket) do
    node = Node.self() |> :erlang.atom_to_binary()
    secret = socket.private.live_stash.secret
    encrypted_node = Phoenix.Token.encrypt(socket, secret, node)
    LiveView.push_event(socket, "live-stash:save-node", %{node: encrypted_node})
  end

  @doc """
  Decrypts the node hint from connect params (e.g. on reconnect).
  Returns the node as an atom or `nil` if missing or decryption fails.
  """
  @spec get_node_hint(LiveView.Socket.t(), map() | nil, String.t()) :: node() | nil
  def get_node_hint(socket, %{"node" => node}, secret) when is_binary(node) do
    {:ok, node} = Phoenix.Token.decrypt(socket, secret, node)
    String.to_existing_atom(node)
  rescue
    error ->
      err = Utils.warning_message("Failed to decode node hint", error)
      Logger.warning(err)
      nil
  end

  def get_node_hint(_socket, _connect_params, _secret), do: nil
end
