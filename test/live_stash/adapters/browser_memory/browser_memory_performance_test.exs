defmodule LiveStash.Adapters.BrowserMemoryPerformanceTest do
  use ExUnit.Case, async: false
  use LiveStash.AdapterPerformanceSuite

  alias LiveStash.Fakes
  alias LiveStash.Adapters.BrowserMemory

  def build_stash_socket(_stash_id, assigns), do: browser_memory_socket(assigns)

  def pre_insert_state(_stash_id, state) do
    stashed =
      state
      |> browser_memory_socket()
      |> BrowserMemory.stash()

    events = get_in(stashed.private, [:live_temp, :push_events]) || []

    ["live-stash:stash-state", %{"assigns" => token}] =
      Enum.find(events, fn [event, _] -> event == "live-stash:stash-state" end)

    token
  end

  def build_recovery_socket(_stash_id, assigns, token) do
    assigns
    |> browser_memory_socket()
    |> put_in(
      [Access.key!(:private), :live_stash_context, Access.key!(:reconnected?)],
      true
    )
    |> put_in(
      [Access.key!(:private), :connect_params],
      %{"liveStash" => %{"stashedState" => token}}
    )
  end

  def adapter_stash(socket), do: BrowserMemory.stash(socket)
  def adapter_recover(socket), do: BrowserMemory.recover_state(socket)

  defp browser_memory_socket(assigns) do
    Fakes.socket(
      assigns: Map.merge(%{__changed__: %{}}, assigns),
      private: %{
        live_temp: %{},
        connect_params: %{},
        live_stash_context: %BrowserMemory.Context{
          stored_keys: Map.keys(assigns),
          reconnected?: false,
          ttl: 86_400,
          secret: "perf_test_secret",
          security_mode: :sign,
          stash_fingerprint: nil
        }
      }
    )
  end
end
