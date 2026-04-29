defmodule LiveStash.Adapters.Common do
  @moduledoc false

  alias Phoenix.LiveView
  alias LiveStash.Utils

  def get_connect_params(socket) do
    try do
      LiveView.get_connect_params(socket)
    rescue
      e in RuntimeError ->
        msg =
          Utils.exception_message(
            "Failed to get connect params. This likely means that LiveStash.init_stash/2 is being called outside of the mount lifecycle or before the socket is fully initialized.",
            e,
            __STACKTRACE__
          )

        reraise RuntimeError.exception(msg), __STACKTRACE__
    end
  end

  def reconnected?(%{"_mounts" => mounts}) when is_integer(mounts), do: mounts > 0
  def reconnected?(_params), do: false

  def maybe_put_secret(attrs, nil, _session), do: attrs

  def maybe_put_secret(attrs, session_key, session) do
    Keyword.put(attrs, :secret, fetch_secret(session_key, session))
  end

  defp fetch_secret(session_key, session) do
    secret =
      try do
        Map.fetch!(session, session_key)
      rescue
        e ->
          msg =
            Utils.exception_message(
              "The provided session_key failed to return a valid secret.",
              e,
              __STACKTRACE__
            )

          reraise ArgumentError.exception(msg), __STACKTRACE__
      end

    if not is_binary(secret) do
      raise ArgumentError,
            "The provided session_key returned an invalid type. Expected a binary string."
    end

    :sha256
    |> :crypto.hash(secret)
    |> Base.encode64(padding: false)
  end

  def validate_attributes!(attrs, allowed_keys) do
    Enum.each(attrs, fn {key, _value} = attr ->
      error_msg =
        if key in allowed_keys do
          validate_attribute(attr)
        else
          "Unknown attribute passed: #{inspect(key)}"
        end

      if error_msg do
        msg = Utils.reason_message(error_msg, :invalid)
        raise ArgumentError, msg
      end
    end)

    attrs
  end

  defp validate_attribute({:security_mode, mode}) when mode not in [:sign, :encrypt] do
    "Invalid security_mode: #{inspect(mode)}. Expected :sign or :encrypt."
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

  defp validate_attribute({:replication, replication}) when not is_boolean(replication) do
    "Invalid replication: #{inspect(replication)}. Expected a boolean."
  end

  defp validate_attribute({:reconnected?, reconnected}) when not is_boolean(reconnected) do
    "Invalid reconnected?: #{inspect(reconnected)}. Expected a boolean."
  end

  defp validate_attribute({:stored_keys, keys}) do
    if is_list(keys) and Enum.all?(keys, &is_atom/1) do
      nil
    else
      "Invalid stored_keys: #{inspect(keys)}. Expected a list of atoms."
    end
  end

  defp validate_attribute({:id, id}) when not is_binary(id) do
    "Invalid id: #{inspect(id)}. Expected a binary string."
  end

  defp validate_attribute(_valid_attr), do: nil
end
