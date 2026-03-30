defmodule Mix.Tasks.E2e do
  @moduledoc false

  use Mix.Task

  @shortdoc "Runs End-to-End tests using Playwright and Docker"
  @app_dir "examples/showcase_app"

  @impl Mix.Task
  def run(_args) do
    IO.puts("\n[E2E] Starting test suite...")

    {docker_cmd, up_args, down_args} = docker_config()

    cleanup_resources(docker_cmd, down_args)

    try do
      IO.puts("[E2E] Booting Docker infrastructure...")
      System.cmd(docker_cmd, up_args, cd: @app_dir)

      IO.puts("[E2E] Starting Phoenix server in test environment...")
      start_phoenix_server()

      wait_for_services()

      IO.puts("[E2E] Executing Playwright tests...")
      run_playwright()
    after
      IO.puts("\n[E2E] Tearing down infrastructure and cleaning up...")
      cleanup_resources(docker_cmd, down_args)
      IO.puts("[E2E] Done.\n")
    end
  end

  defp docker_config do
    cmd = if System.find_executable("docker-compose"), do: "docker-compose", else: "docker"
    up_args = if cmd == "docker", do: ["compose", "up", "-d"], else: ["up", "-d"]
    down_args = if cmd == "docker", do: ["compose", "down"], else: ["down"]

    {cmd, up_args, down_args}
  end

  defp cleanup_resources(docker_cmd, down_args) do
    System.cmd("sh", ["-c", "lsof -t -i:4000 | xargs kill -9 > /dev/null 2>&1"])
    System.cmd(docker_cmd, down_args, cd: @app_dir, stderr_to_stdout: true)
  end

  defp start_phoenix_server do
    spawn(fn ->
      try do
        System.cmd("mix", ["phx.server"],
          cd: @app_dir,
          env: [{"MIX_ENV", "test"}],
          into: IO.stream(:stdio, :line)
        )
      rescue
        e ->
          IO.puts("\n[E2E ERROR] Background Phoenix process crashed: #{inspect(e)}\n")
      end
    end)
  end

  defp wait_for_services(max_attempts \\ 60) do
    IO.puts("[E2E] Waiting for services (Nginx: 8080, Phoenix: 4000) to become available...")

    Enum.reduce_while(1..max_attempts, :error, fn attempt, _acc ->
      nginx_status = check_http_status(8080)
      phoenix_status = check_http_status(4000)

      cond do
        nginx_status == "200" and phoenix_status == "200" ->
          IO.puts("[E2E] Services are ready (200 OK).")
          Process.sleep(2000)
          {:halt, :ok}

        attempt == max_attempts ->
          Mix.raise(
            "[E2E ERROR] Timeout. Services failed to start within #{max_attempts * 2} seconds."
          )

        true ->
          Process.sleep(2000)
          {:cont, :error}
      end
    end)
  end

  defp check_http_status(port) do
    {out, _} =
      System.cmd("curl", [
        "-s",
        "-o",
        "/dev/null",
        "-w",
        "%{http_code}",
        "-m",
        "2",
        "http://127.0.0.1:#{port}/"
      ])

    String.trim(out)
  end

  defp run_playwright do
    System.cmd("sh", ["-c", "npx playwright test --project=firefox --workers=1"],
      cd: @app_dir,
      into: IO.stream(:stdio, :line)
    )
  end
end
