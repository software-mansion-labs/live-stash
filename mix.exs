defmodule LiveStash.MixProject do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :live_stash,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
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
      {:uniq, "~> 0.6"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:makeup_js, "~> 0.1.0", only: :dev, runtime: false},
      {:makeup_eex, "~> 2.0", only: :dev, runtime: false},
      {:makeup_html, "~> 0.2", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      "test.all": ["test", "e2e"]
    ]
  end

  defp docs() do
    [
      main: "welcome",
      extras: [
        "CHANGELOG.md",
        "docs/welcome.md",
        "docs/browser_memory.md",
        "docs/ets.md",
        "docs/adapters.md",
        "docs/example.md"
      ],
      groups_for_extras: [
        Adapters: [
          "docs/browser_memory.md",
          "docs/ets.md",
          "docs/adapters.md"
        ]
      ],
      source_url: "https://github.com/software-mansion-labs/live-stash",
      source_ref: "v#{@version}",
      filter_modules: &filter_modules/2
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/software-mansion-labs/live-stash",
        "Changelog" => "https://hexdocs.pm/live_stash/changelog.html"
      },
      files: ~w(assets lib mix.exs LICENSE README.md CHANGELOG.md)
    ]
  end

  defp filter_modules(LiveStash, _meta), do: true
  defp filter_modules(LiveStash.Adapter, _meta), do: true
  defp filter_modules(LiveStash.Adapters.BrowserMemory, _meta), do: true
  defp filter_modules(LiveStash.Adapters.ETS, _meta), do: true
  defp filter_modules(_, _meta), do: false

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
