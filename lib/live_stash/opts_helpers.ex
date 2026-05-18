defmodule LiveStash.OptsHelpers do
  @moduledoc false

  alias LiveStash.Utils

  def ensure_stored_keys!(attrs) do
    unless Keyword.has_key?(attrs, :stored_keys) do
      msg =
        Utils.reason_message(
          "Missing required option: :stored_keys. You must define which assigns to persist. Example: use LiveStash, stored_keys: [:count]",
          :invalid
        )

      raise ArgumentError, msg
    end
  end

  def ensure_adapter_active!(adapter) do
    active_adapters = Application.get_env(:live_stash, :adapters, [LiveStash.Adapter.default()])

    if adapter not in active_adapters do
      msg =
        Utils.reason_message(
          "The adapter #{inspect(adapter)} is not active. Please add it to the :adapters list in your :live_stash config.",
          :invalid
        )

      raise ArgumentError, msg
    end
  end

  def handle_auto_stash(socket, opts) do
    {auto_stash?, _opts} = Keyword.pop(opts, :auto_stash, false)

    if auto_stash? do
      Phoenix.LiveView.attach_hook(
        socket,
        :live_stash_auto_stash,
        :after_render,
        &LiveStash.stash/1
      )
    else
      socket
    end
  end
end
