defmodule LiveStash.ComponentTest do
  use ExUnit.Case, async: false

  alias LiveStash.Component
  alias LiveStash.Fakes

  defmodule BareComponent do
    use LiveStash.Component, stored_keys: [:count, :name]
  end

  defmodule ComponentWithMountStashed do
    use LiveStash.Component, stored_keys: [:count]

    def mount_stashed(socket) do
      Phoenix.Component.assign(socket, :mount_stashed_calls, [
        socket.private[:live_stash_recovered?] | socket.assigns[:mount_stashed_calls] || []
      ])
    end
  end

  setup do
    Process.delete(:live_stash_components)
    :ok
  end

  defp component_socket(assigns, private \\ %{}) do
    socket = Fakes.socket(assigns: assigns, private: private)
    %{socket | root_pid: self()}
  end

  describe "__before_update__/4 — first call, no recovered state" do
    test "sets :live_stash_recovered? to false" do
      socket = component_socket(%{__changed__: %{}, id: "a"})

      result =
        Component.__before_update__(socket, %{id: "a"}, [stored_keys: [:count]], BareComponent)

      assert result.private[:live_stash_recovered?] == false
    end

    test "stores module and opts in socket.private for later stash/1 use" do
      socket = component_socket(%{__changed__: %{}, id: "a"})
      opts = [stored_keys: [:count]]

      result = Component.__before_update__(socket, %{id: "a"}, opts, BareComponent)

      assert result.private[:live_stash_component_module] == BareComponent
      assert result.private[:live_stash_component_opts] == opts
    end

    test "does not modify assigns when nothing was recovered" do
      socket = component_socket(%{__changed__: %{}, id: "a", count: 7})

      result =
        Component.__before_update__(socket, %{id: "a"}, [stored_keys: [:count]], BareComponent)

      assert result.assigns.count == 7
    end
  end

  describe "__before_update__/4 — first call, recovered state present" do
    test "merges recovered assigns into the socket and sets flag true" do
      Process.put(:live_stash_components, %{
        {BareComponent, "a"} => %{count: 42, name: "alice"}
      })

      socket = component_socket(%{__changed__: %{}, id: "a"})

      result =
        Component.__before_update__(
          socket,
          %{id: "a"},
          [stored_keys: [:count, :name]],
          BareComponent
        )

      assert result.assigns.count == 42
      assert result.assigns.name == "alice"
      assert result.private[:live_stash_recovered?] == true
    end

    test "removes the consumed entry from the process dictionary" do
      Process.put(:live_stash_components, %{
        {BareComponent, "a"} => %{count: 1},
        {BareComponent, "b"} => %{count: 2}
      })

      socket = component_socket(%{__changed__: %{}, id: "a"})

      Component.__before_update__(
        socket,
        %{id: "a"},
        [stored_keys: [:count]],
        BareComponent
      )

      remaining = Process.get(:live_stash_components)
      assert remaining == %{{BareComponent, "b"} => %{count: 2}}
    end

    test "treats different (module, id) pairs as independent slices" do
      Process.put(:live_stash_components, %{
        {BareComponent, "a"} => %{count: 1},
        {ComponentWithMountStashed, "a"} => %{count: 99}
      })

      socket = component_socket(%{__changed__: %{}, id: "a"})

      result =
        Component.__before_update__(
          socket,
          %{id: "a"},
          [stored_keys: [:count]],
          BareComponent
        )

      assert result.assigns.count == 1

      assert Process.get(:live_stash_components) == %{
               {ComponentWithMountStashed, "a"} => %{count: 99}
             }
    end
  end

  describe "__before_update__/4 — subsequent calls" do
    test "is idempotent once :live_stash_recovered? is set (true)" do
      socket =
        component_socket(
          %{__changed__: %{}, id: "a", count: 5},
          %{live_stash_recovered?: true}
        )

      Process.put(:live_stash_components, %{{BareComponent, "a"} => %{count: 999}})

      result =
        Component.__before_update__(socket, %{id: "a"}, [stored_keys: [:count]], BareComponent)

      assert result.assigns.count == 5
      assert Process.get(:live_stash_components) == %{{BareComponent, "a"} => %{count: 999}}
    end

    test "is idempotent once :live_stash_recovered? is set (false)" do
      socket =
        component_socket(
          %{__changed__: %{}, id: "a", count: 5},
          %{live_stash_recovered?: false}
        )

      Process.put(:live_stash_components, %{{BareComponent, "a"} => %{count: 999}})

      result =
        Component.__before_update__(socket, %{id: "a"}, [stored_keys: [:count]], BareComponent)

      assert result.assigns.count == 5
      assert Process.get(:live_stash_components) == %{{BareComponent, "a"} => %{count: 999}}
    end
  end

  describe "__before_update__/4 — mount_stashed callback" do
    test "is called on first invocation when defined" do
      socket = component_socket(%{__changed__: %{}, id: "a"})

      result =
        Component.__before_update__(
          socket,
          %{id: "a"},
          [stored_keys: [:count]],
          ComponentWithMountStashed
        )

      assert result.assigns.mount_stashed_calls == [false]
    end

    test "sees :live_stash_recovered? = true when state was recovered" do
      Process.put(:live_stash_components, %{{ComponentWithMountStashed, "a"} => %{count: 1}})

      socket = component_socket(%{__changed__: %{}, id: "a"})

      result =
        Component.__before_update__(
          socket,
          %{id: "a"},
          [stored_keys: [:count]],
          ComponentWithMountStashed
        )

      assert result.assigns.mount_stashed_calls == [true]
    end

    test "is not called on subsequent invocations" do
      socket =
        component_socket(
          %{__changed__: %{}, id: "a", mount_stashed_calls: [false]},
          %{live_stash_recovered?: false}
        )

      result =
        Component.__before_update__(
          socket,
          %{id: "a"},
          [stored_keys: [:count]],
          ComponentWithMountStashed
        )

      assert result.assigns.mount_stashed_calls == [false]
    end

    test "is skipped silently when not defined on the module" do
      socket = component_socket(%{__changed__: %{}, id: "a"})

      result =
        Component.__before_update__(socket, %{id: "a"}, [stored_keys: [:count]], BareComponent)

      assert result.private[:live_stash_recovered?] == false
    end
  end

  describe "__before_update__/4 — invalid input" do
    test "raises a clear ArgumentError when assigns is missing :id" do
      socket = component_socket(%{__changed__: %{}})

      assert_raise ArgumentError, ~r/requires an `id` assign/, fn ->
        Component.__before_update__(socket, %{}, [stored_keys: [:count]], BareComponent)
      end
    end

    test "raises when :id is not a binary or integer" do
      socket = component_socket(%{__changed__: %{}, id: %{}})

      assert_raise ArgumentError, ~r/requires an `id` assign/, fn ->
        Component.__before_update__(socket, %{id: %{}}, [stored_keys: [:count]], BareComponent)
      end
    end
  end

  describe "stash/1" do
    test "sends {:live_stash_component_stash, key, assigns_to_stash} to root_pid" do
      socket =
        component_socket(
          %{__changed__: %{}, id: "a", count: 7, name: "alice", extra: :ignored},
          %{
            live_stash_recovered?: false,
            live_stash_component_module: BareComponent,
            live_stash_component_opts: [stored_keys: [:count, :name]]
          }
        )

      Component.stash(socket)

      assert_receive {:live_stash_component_stash, {BareComponent, "a"},
                      %{count: 7, name: "alice"}}
    end

    test "filters assigns_to_stash by stored_keys (drops untracked keys)" do
      socket =
        component_socket(
          %{__changed__: %{}, id: "a", count: 1, ephemeral: :nope},
          %{
            live_stash_recovered?: false,
            live_stash_component_module: BareComponent,
            live_stash_component_opts: [stored_keys: [:count]]
          }
        )

      Component.stash(socket)

      assert_receive {:live_stash_component_stash, {BareComponent, "a"}, payload}
      assert payload == %{count: 1}
    end

    test "returns the socket unchanged" do
      socket =
        component_socket(
          %{__changed__: %{}, id: "a", count: 1},
          %{
            live_stash_recovered?: false,
            live_stash_component_module: BareComponent,
            live_stash_component_opts: [stored_keys: [:count]]
          }
        )

      assert Component.stash(socket) == socket
    end

    test "raises when called before __before_update__ has populated context" do
      socket = component_socket(%{__changed__: %{}, id: "a", count: 1})

      assert_raise ArgumentError, ~r/Missing private key/, fn ->
        Component.stash(socket)
      end
    end
  end

  describe "macro-generated update/2" do
    test "wraps __before_update__ and merges parent assigns into socket" do
      socket = component_socket(%{__changed__: %{}})

      assert {:ok, result} = BareComponent.update(%{id: "a", count: 3, name: "x"}, socket)

      assert result.assigns.id == "a"
      assert result.assigns.count == 3
      assert result.assigns.name == "x"
      assert result.private[:live_stash_recovered?] == false
    end

    test "second invocation does not re-trigger recovery" do
      Process.put(:live_stash_components, %{{BareComponent, "a"} => %{count: 999}})

      socket = component_socket(%{__changed__: %{}})

      {:ok, after_first} = BareComponent.update(%{id: "a", count: 1}, socket)

      assert Process.get(:live_stash_components) == %{}
      assert after_first.assigns.count == 1

      Process.put(:live_stash_components, %{{BareComponent, "a"} => %{count: 555}})
      {:ok, after_second} = BareComponent.update(%{id: "a", count: 2}, after_first)

      assert after_second.assigns.count == 2
      assert Process.get(:live_stash_components) == %{{BareComponent, "a"} => %{count: 555}}
    end
  end
end
