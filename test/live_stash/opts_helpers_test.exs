defmodule LiveStash.OptsHelpersTest do
  use ExUnit.Case, async: true

  alias LiveStash.Fakes
  alias LiveStash.OptsHelpers

  describe "ensure_stored_keys!/1" do
    test "passes when :stored_keys is present" do
      OptsHelpers.ensure_stored_keys!(stored_keys: [:count])
    end

    test "raises ArgumentError when :stored_keys is missing from empty opts" do
      assert_raise ArgumentError, ~r/Missing required option: :stored_keys/, fn ->
        OptsHelpers.ensure_stored_keys!([])
      end
    end

    test "raises ArgumentError when :stored_keys is missing from non-empty opts" do
      assert_raise ArgumentError, ~r/Missing required option: :stored_keys/, fn ->
        OptsHelpers.ensure_stored_keys!(ttl: 5)
      end
    end
  end

  describe "ensure_adapter_active!/1" do
    test "passes when adapter is in the active adapters list" do
      OptsHelpers.ensure_adapter_active!(LiveStash.Adapters.ETS)
    end

    test "raises ArgumentError when adapter is not in the active adapters list" do
      assert_raise ArgumentError, ~r/is not active/, fn ->
        OptsHelpers.ensure_adapter_active!(SomeOtherAdapter)
      end
    end
  end

  describe "handle_auto_stash/2" do
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

    test "does not attach after_render hook when auto_stash default", %{socket: socket} do
      result = OptsHelpers.handle_auto_stash(socket, stored_keys: [:count])
      refute has_auto_stash_hook?(result)
    end

    test "does not attach after_render hook when auto_stash explicitly false", %{socket: socket} do
      result = OptsHelpers.handle_auto_stash(socket, stored_keys: [:count], auto_stash: false)
      refute has_auto_stash_hook?(result)
    end

    test "attaches after_render hook when auto_stash: true", %{socket: socket} do
      result = OptsHelpers.handle_auto_stash(socket, stored_keys: [:count], auto_stash: true)
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
