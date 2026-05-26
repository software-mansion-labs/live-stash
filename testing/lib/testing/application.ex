defmodule Testing.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TestingWeb.Telemetry,
      Testing.PromEx,
      {DNSCluster, query: Application.get_env(:testing, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Testing.PubSub},
      # Start a worker by calling: Testing.Worker.start_link(arg)
      # {Testing.Worker, arg},
      # Start to serve requests, typically the last entry
      TestingWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Testing.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TestingWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
