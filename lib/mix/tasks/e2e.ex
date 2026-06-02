defmodule Mix.Tasks.E2e do
  @moduledoc false

  use Mix.Task

  @shortdoc "Runs End-to-End tests using Playwright and Docker"
  @app_dir "testing"

  @nginx_port 8080
  @phoenix_port 4000

  @impl Mix.Task
  def run(_args) do
    IO.puts("\n[E2E] Starting test suite...")

    install_npm_deps()

    {docker_cmd, up_args, down_args} = docker_config()

    cleanup_resources(docker_cmd, down_args)

    exit_status =
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

    if exit_status != 0 do
      System.halt(exit_status)
    end
  end

  defp docker_config do
    cmd = if System.find_executable("docker-compose"), do: "docker-compose", else: "docker"
    file_args = ["-f", "docker-compose.e2e.yml"]

    up_args =
      if cmd == "docker",
        do: ["compose"] ++ file_args ++ ["up", "-d"],
        else: file_args ++ ["up", "-d"]

    down_args =
      if cmd == "docker", do: ["compose"] ++ file_args ++ ["down"], else: file_args ++ ["down"]

    {cmd, up_args, down_args}
  end

  defp cleanup_resources(docker_cmd, down_args) do
    System.cmd("sh", ["-c", "lsof -t -i:#{@phoenix_port} | xargs kill -9 > /dev/null 2>&1"])
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

  defp wait_for_services(max_attempts \\ 120, attempt_interval \\ 2) do
    IO.puts(
      "[E2E] Waiting for services (Nginx: #{@nginx_port}, Phoenix: #{@phoenix_port}) to become available..."
    )

    Enum.reduce_while(1..max_attempts, :error, fn attempt, _acc ->
      nginx_status = check_http_status(@nginx_port)
      phoenix_status = check_http_status(@phoenix_port)

      cond do
        nginx_status == "200" and phoenix_status == "200" ->
          IO.puts("[E2E] Services are ready (200 OK).")
          Process.sleep(attempt_interval * 1000)
          {:halt, :ok}

        attempt == max_attempts ->
          Mix.raise(
            "[E2E ERROR] Timeout. Services failed to start within #{max_attempts * attempt_interval} seconds. Last status - Nginx: #{nginx_status}, Phoenix: #{phoenix_status}"
          )

        true ->
          Process.sleep(attempt_interval * 1000)
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
    {_stream, status} =
      System.cmd("sh", ["-c", "npx playwright test --project=firefox --workers=1"],
        cd: @app_dir,
        into: IO.stream(:stdio, :line)
      )

    status
  end

  defp install_npm_deps do
    {_stream, status} =
      System.cmd(
        "npm",
        ["install", "--no-fund", "--no-audit"],
        cd: @app_dir,
        into: IO.stream(:stdio, :line)
      )

    if status != 0 do
      Mix.raise("[E2E ERROR] Failed to install NPM dependencies. Please check the logs above.")
    end
  end
end
