defmodule LiveStash.Adapters.Redis.Helpers do
  @moduledoc false

  @compile {:no_warn_undefined, [Redix, Redix.Error, Redix.ConnectionError]}

  alias LiveStash.Utils

  @conn_name LiveStash.Adapters.Redis.Conn
  @conn_options [name: @conn_name, sync_connect: false]

  @stash_script_path Path.join([__DIR__, "scripts", "stash.lua"])
  @external_resource @stash_script_path
  @stash_script File.read!(@stash_script_path)
  @stash_script_hash :crypto.hash(:sha, @stash_script) |> Base.encode16(case: :lower)

  @recover_script_path Path.join([__DIR__, "scripts", "recover.lua"])
  @external_resource @recover_script_path
  @recover_script File.read!(@recover_script_path)
  @recover_script_hash :crypto.hash(:sha, @recover_script) |> Base.encode16(case: :lower)

  @doc """
  Returns the Redix `start_link` arguments derived from `:live_stash, :redis`
  application config.
  """
  def redix_args do
    case Application.get_env(:live_stash, :redis, []) do
      uri when is_binary(uri) ->
        {uri, @conn_options}

      {uri, extra_opts} when is_binary(uri) and is_list(extra_opts) ->
        {uri, Keyword.merge(extra_opts, @conn_options)}

      config_opts when is_list(config_opts) ->
        Keyword.merge(config_opts, @conn_options)

      invalid ->
        msg =
          Utils.reason_message(
            "Invalid :live_stash, :redis configuration: #{inspect(invalid)}. " <>
              "Expected one of: a Redis URI string, a {uri, options} tuple, " <>
              "or a keyword list of Redix options.",
            :invalid
          )

        raise ArgumentError, msg
    end
  end

  @doc """
  Runs a raw Redix command against the adapter's connection.
  """
  def command(cmd) do
    Redix.command(@conn_name, cmd)
  end

  @doc """
  Stashes `payload` under `key` for the given `owner_id`, refreshing the TTL.

  Returns `{:error, :ownership_mismatch}` if the key already belongs to a
  different owner, otherwise `:ok` on success or `{:error, formatted_error}`
  on connection / Redis errors.
  """
  def save(key, owner_id, payload, ttl) do
    case eval_script(@stash_script, @stash_script_hash, [key], [owner_id, payload, ttl]) do
      {:ok, "OK"} ->
        :ok

      {:error, %Redix.Error{message: "Ownership mismatch"}} ->
        {:error, :ownership_mismatch}

      {:error, error} ->
        {:error, format_error("Failed to stash assigns", error)}
    end
  end

  @doc """
  Recovers the payload stored under `key` and atomically takes ownership for
  `new_owner_id`, refreshing the TTL.

  Returns `{:ok, binary}` when a payload was found, `{:ok, :not_found}` when
  the key does not exist, or `{:error, formatted_error}` on Redis errors.
  """
  def recover(key, new_owner_id, ttl) do
    case eval_script(@recover_script, @recover_script_hash, [key], [new_owner_id, ttl]) do
      {:ok, nil} ->
        {:ok, :not_found}

      {:ok, binary} when is_binary(binary) ->
        {:ok, binary}

      {:error, error} ->
        {:error, format_error("Failed to recover state", error)}
    end
  end

  @doc """
  Deletes the stash entry stored under `key`.
  """
  def delete(key) do
    case command(["DEL", key]) do
      {:ok, _count} ->
        :ok

      {:error, error} ->
        {:error, format_error("Failed to delete stash for key #{key}", error)}
    end
  end

  @doc """
  Refreshes the TTL on `key` without touching its contents.
  """
  def bump_ttl(key, ttl) do
    case command(["EXPIRE", key, to_string(ttl)]) do
      {:ok, _} ->
        :ok

      {:error, error} ->
        {:error, format_error("Failed to refresh stash for key #{key}", error)}
    end
  end

  defp eval_script(script, script_hash, keys, args) do
    num_keys = length(keys)

    normalized_args =
      Enum.map(args, fn
        arg when is_integer(arg) -> Integer.to_string(arg)
        arg -> arg
      end)

    cmd_args = [to_string(num_keys)] ++ keys ++ normalized_args

    case command(["EVALSHA", script_hash | cmd_args]) do
      {:error, %Redix.Error{message: "NOSCRIPT" <> _}} ->
        command(["EVAL", script | cmd_args])

      result ->
        result
    end
  end

  defp format_error(message, %Redix.Error{} = redis_error) do
    Utils.exception_message("#{message} - Redis error", redis_error)
  end

  defp format_error(message, %Redix.ConnectionError{} = conn_error) do
    Utils.reason_message("#{message} - Redis connection error", conn_error)
  end

  defp format_error(message, other) do
    Utils.reason_message(message, other)
  end
end
