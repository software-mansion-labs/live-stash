defmodule LiveStash.Adapters.ETS.Context do
  @moduledoc """
  Holds the state and configuration for the ETS adapter.
  ## Fields
  * `:stored_keys` - A list of assign keys to automatically stash on every update.
  * `:reconnected?` - A boolean indicating whether the LiveView socket has successfully reconnected vs. a fresh mount.
  * `:stash_fingerprint` - A binary string representing the fingerprint of the stashed state. This is used to determine if the state has changed and needs to be re-stashed.
  * `:id` - A unique identifier (UUID) representing the specific stash instance stored in the ETS table.
  * `:secret` - A binary string used as part of the record id in the ETS for security purposes.
  * `:ttl` - Time-to-live for the records kept in the ETS table, specified in milliseconds.
  * `:node_hint` - Information about the Elixir node that currently holds stashed state in the ETS. This is used to optimize state retrieval in a distributed deployment.
  """

  alias LiveStash.Adapters.ETS.NodeHint
  alias Phoenix.LiveView
  alias LiveStash.Adapters.Common
  alias LiveStash.Utils

  @enforce_keys [
    :stored_keys,
    :reconnected?,
    :id
  ]

  defstruct [
    :stored_keys,
    :reconnected?,
    :id,
    stash_fingerprint: nil,
    secret: "live_stash",
    ttl: 5 * 60 * 1000,
    node_hint: nil
  ]

  @type t :: %__MODULE__{
          stored_keys: [atom()],
          reconnected?: boolean(),
          stash_fingerprint: binary() | nil,
          secret: binary(),
          ttl: integer(),
          node_hint: atom() | nil,
          id: binary()
        }

  @allowed_keys [
    :stored_keys,
    :reconnected?,
    :stash_fingerprint,
    :secret,
    :ttl,
    :id
  ]

  @doc """
  Builds context from socket, session and opts (e.g. in `on_mount` / `init_stash`).
  """
  @spec new(LiveView.Socket.t(), keyword(), keyword()) :: t()
  def new(socket, session, opts) do
    {session_key, base_attrs} = Keyword.pop(opts, :session_key)

    attrs = Common.maybe_put_secret(base_attrs, session_key, session)

    connect_params = Common.get_connect_params(socket) || %{}

    context =
      attrs
      |> Keyword.put(:reconnected?, Common.reconnected?(connect_params))
      |> Keyword.put(:id, get_in(connect_params, ["liveStash", "stashId"]) || Uniq.UUID.uuid4())
      |> validate_attributes!()
      |> then(&struct!(__MODULE__, &1))

    node_hint = NodeHint.get_node_hint(socket, connect_params, context.secret)

    %{context | node_hint: node_hint}
  end

  defp validate_attributes!(attrs) do
    Enum.each(attrs, fn attr ->
      if error_msg = validate_attribute(attr) do
        msg = Utils.reason_message(error_msg, :invalid)
        raise ArgumentError, msg
      end
    end)

    attrs
  end

  defp validate_attribute({:ttl, ttl}) when not is_integer(ttl) do
    "Invalid ttl: #{inspect(ttl)}. Expected an integer."
  end

  defp validate_attribute({:secret, secret}) when not is_binary(secret) do
    "Invalid secret: #{inspect(secret)}. Expected a binary string."
  end

  defp validate_attribute({:stash_fingerprint, fp}) when not (is_binary(fp) or is_nil(fp)) do
    "Invalid stash_fingerprint: #{inspect(fp)}. Expected a binary or nil."
  end

  defp validate_attribute({:reconnected?, reconnected}) when not is_boolean(reconnected) do
    "Invalid reconnected?: #{inspect(reconnected)}. Expected a boolean."
  end

  defp validate_attribute({:id, id}) when not is_binary(id) do
    "Invalid id: #{inspect(id)}. Expected a binary string."
  end

  defp validate_attribute({:stored_keys, keys}) do
    if is_list(keys) and Enum.all?(keys, &is_atom/1) do
      nil
    else
      "Invalid stored_keys: #{inspect(keys)}. Expected a list of atoms."
    end
  end

  defp validate_attribute({unknown_key, _value}) when unknown_key not in @allowed_keys do
    "Unknown attribute passed: #{inspect(unknown_key)}"
  end

  defp validate_attribute(_valid_attr), do: nil
end
