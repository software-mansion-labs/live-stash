defmodule LiveStashTest do
  use ExUnit.Case, async: true

  alias LiveStash.Fakes

  setup do
    socket =
      Fakes.socket(
        assigns: %{},
        private: %{
          live_temp: %{},
          connect_params: %{},
          lifecycle: %Phoenix.LiveView.Lifecycle{}
        }
      )

    {:ok, socket: socket}
  end

  describe "init_stash/3" do
    for {label, opts} <- [
          {"omitted (default)", [stored_keys: [:count]]},
          {"explicitly false", [stored_keys: [:count], auto_stash: false]}
        ] do
      test "does not attach after_render hook when auto_stash #{label}", %{socket: socket} do
        result = LiveStash.init_stash(socket, %{}, unquote(opts))
        refute has_auto_stash_hook?(result)
      end
    end

    test "attaches after_render hook when auto_stash: true", %{socket: socket} do
      result = LiveStash.init_stash(socket, %{}, stored_keys: [:count], auto_stash: true)
      assert has_auto_stash_hook?(result)
    end
  end

  defp has_auto_stash_hook?(socket) do
    %{after_render: hooks} = socket.private.lifecycle

    Enum.any?(hooks, fn
      %{id: id} -> id == :live_stash_auto_stash
      {id, _function} -> id == :live_stash_auto_stash
    end)
  end
end
