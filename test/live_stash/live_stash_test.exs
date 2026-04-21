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

  test "init_stash/3 attaches after_render hook when auto_stash is true by default", %{
    socket: socket
  } do
    socket_with_hook = LiveStash.init_stash(socket, %{}, stored_keys: [:count])

    assert %{after_render: hooks} = socket_with_hook.private.lifecycle

    assert Enum.any?(hooks, fn
             %{id: id} -> id == :live_stash_auto_stash
             {id, _function} -> id == :live_stash_auto_stash
           end)
  end

  test "init_stash/3 does not attach after_render hook when auto_stash is false", %{
    socket: socket
  } do
    socket_without_hook =
      LiveStash.init_stash(socket, %{}, stored_keys: [:count], auto_stash: false)

    assert %{after_render: hooks} = socket_without_hook.private.lifecycle

    refute Enum.any?(hooks, fn
             %{id: id} -> id == :live_stash_auto_stash
             {id, _function} -> id == :live_stash_auto_stash
           end)
  end

  test "init_stash/3 accepts explicit auto_stash true", %{socket: socket} do
    socket_with_hook =
      LiveStash.init_stash(socket, %{}, stored_keys: [:count], auto_stash: true)

    assert %{after_render: hooks} = socket_with_hook.private.lifecycle

    assert Enum.any?(hooks, fn
             %{id: id} -> id == :live_stash_auto_stash
             {id, _function} -> id == :live_stash_auto_stash
           end)
  end
end
