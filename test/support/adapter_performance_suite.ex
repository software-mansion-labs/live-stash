defmodule LiveStash.AdapterPerformanceSuite do
  @moduledoc """
  Shared ExUnit performance suite injected into every adapter performance test.

  Using modules must implement five adapter-specific callbacks:

    * `build_stash_socket/2` — returns a socket ready for `stash/1`
    * `pre_insert_state/2` — persists state ahead of a recovery test and returns
      opaque `recovery_data` (e.g. an ETS ID, encoded token, Redis key …)
    * `build_recovery_socket/3` — returns a socket ready for `recover_state/1`,
      given the `recovery_data` returned by `pre_insert_state/2`
    * `adapter_stash/1` — delegates to the adapter's `stash/1`
    * `adapter_recover/1` — delegates to the adapter's `recover_state/1`

  All adapters run the same six scenarios so results are directly comparable.
  """

  defmacro __using__(_opts) do
    quote do
      import LiveStash.PerformanceHelpers, only: [measure_ms: 1, large_binary: 1, large_map: 1]

      @moduletag :performance
      @moduletag timeout: 60_000

      defp perf_label do
        __MODULE__
        |> Module.split()
        |> List.last()
        |> String.replace("PerformanceTest", "")
      end

      defp perf_print(label, ms) do
        IO.puts("  [#{perf_label()}] #{label}: #{Float.round(ms, 2)} ms")
      end

      describe "large number of LiveViews" do
        @live_view_count 2_000

        test "#{@live_view_count} concurrent stash operations complete" do
          sockets =
            for i <- 1..@live_view_count do
              build_stash_socket("perf_stash_#{i}", %{value: "data_#{i}"})
            end

          {ms, _} =
            measure_ms(fn ->
              sockets
              |> Enum.map(&Task.async(fn -> adapter_stash(&1) end))
              |> Task.await_many(60_000)
            end)

          perf_print("#{@live_view_count} concurrent stash", ms)
        end

        test "#{@live_view_count} concurrent recover_state operations complete" do
          recovery_sockets =
            for i <- 1..@live_view_count do
              id = "perf_recover_#{i}"
              recovery_data = pre_insert_state(id, %{value: i})
              build_recovery_socket(id, %{}, recovery_data)
            end

          {ms, results} =
            measure_ms(fn ->
              recovery_sockets
              |> Enum.map(&Task.async(fn -> adapter_recover(&1) end))
              |> Task.await_many(60_000)
            end)

          perf_print("#{@live_view_count} concurrent recover", ms)

          assert Enum.all?(results, fn {status, _} -> status in [:recovered, :not_found] end)
        end
      end

      describe "large payloads" do
        test "stash a 5 MB binary payload" do
          socket = build_stash_socket("perf_large_bin_stash", %{data: large_binary(5_000_000)})

          {ms, _} = measure_ms(fn -> adapter_stash(socket) end)

          perf_print("stash 5 MB binary", ms)
        end

        test "recover a 5 MB binary payload" do
          id = "perf_large_bin_recover"
          data = %{data: large_binary(5_000_000)}
          recovery_data = pre_insert_state(id, data)
          socket = build_recovery_socket(id, %{}, recovery_data)

          {ms, {status, _}} = measure_ms(fn -> adapter_recover(socket) end)

          perf_print("recover 5 MB binary", ms)

          assert status == :recovered, "Expected :recovered, got #{inspect(status)}"
        end

        test "stash a map with 5 000 keys" do
          socket = build_stash_socket("perf_large_map_stash", large_map(5_000))

          {ms, _} = measure_ms(fn -> adapter_stash(socket) end)

          perf_print("stash 5000-key map", ms)
        end

        test "recover a map with 5 000 keys" do
          id = "perf_large_map_recover"
          recovery_data = pre_insert_state(id, large_map(5_000))
          socket = build_recovery_socket(id, %{}, recovery_data)

          {ms, {status, _}} = measure_ms(fn -> adapter_recover(socket) end)

          perf_print("recover 5000-key map", ms)

          assert status == :recovered, "Expected :recovered, got #{inspect(status)}"
        end
      end

      describe "repeated stash operations" do
        @repeated_stash_count 1_000

        test "#{@repeated_stash_count} sequential stash calls on changing state" do
          {ms, _} =
            measure_ms(fn ->
              for i <- 1..@repeated_stash_count do
                build_stash_socket("perf_repeated", %{counter: i})
                |> adapter_stash()
              end
            end)

          perf_print("#{@repeated_stash_count}x sequential stash (state change every call)", ms)
        end
      end
    end
  end
end
