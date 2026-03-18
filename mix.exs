defmodule LiveStash.MixProject do
  use Mix.Project

  @version "0.1.0-dev"

  def project do
    [
      app: :live_stash,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      name: "LiveStash",
      description: "Library that fixes problem of losing state on LiveView reconnects"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {LiveStash.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix_live_view, "~> 1.0"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:uuid, "~> 1.1"}
    ]
  end

  defp docs() do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      source_url: "https://github.com/software-mansion-labs/live-stash",
      source_ref: @version,
      filter_modules: &filter_modules/2
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{github: "https://github.com/software-mansion-labs/live-stash"},
      files: ~w(assets lib mix.exs LICENSE README.md)
    ]
  end

  defp filter_modules(LiveStash, _meta), do: true
  defp filter_modules(LiveStash.Stash, _meta), do: true
  defp filter_modules(LiveStash.Client, _meta), do: true
  defp filter_modules(LiveStash.Server, _meta), do: true
  defp filter_modules(_, _meta), do: false
end
