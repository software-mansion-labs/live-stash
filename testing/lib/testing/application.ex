defmodule Testing.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # CLUSTER_HOSTS is a comma-separated list of node names to connect to, e.g.
    # "testing@10.10.0.3,testing@10.10.0.4". When unset (e.g. the local Docker
    # stack) we fall back to the placeholder hosts so behaviour is unchanged.
    cluster_hosts =
      case System.get_env("CLUSTER_HOSTS") do
        nil -> [:"a@node_a", :"b@node_b"]
        "" -> [:"a@node_a", :"b@node_b"]
        value -> value |> String.split(",", trim: true) |> Enum.map(&String.to_atom/1)
      end

    topologies = [
      example: [
        strategy: Cluster.Strategy.Epmd,
        config: [hosts: cluster_hosts]
      ]
    ]

    children = [
      {Cluster.Supervisor, [topologies, [name: Testing.ClusterSupervisor]]},
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
