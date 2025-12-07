defmodule UzuPattern.MixProject do
  use Mix.Project

  @version "0.6.0"
  @source_url "https://github.com/rpmessner/uzu_pattern"

  def project do
    [
      app: :uzu_pattern,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "UzuPattern",
      source_url: @source_url,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # {:uzu_parser, "~> 0.4.0"},
      {:uzu_parser, path: "../uzu_parser", override: true},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp description do
    "Pattern orchestration library for Strudel.js-style transformations. " <>
      "Time modifiers, combinators, effects, and rhythmic functions. Works with UzuParser."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "ROADMAP.md",
        "CHANGELOG.md": [title: "Changelog"],
        "CONTRIBUTING.md": [title: "Contributing"]
      ],
      groups_for_modules: [
        Core: [UzuPattern, UzuPattern.Pattern],
        "Time Modifiers": [UzuPattern.Pattern.Time],
        Combinators: [UzuPattern.Pattern.Combinators],
        "Conditional Modifiers": [UzuPattern.Pattern.Conditional],
        "Effects & Parameters": [UzuPattern.Pattern.Effects],
        "Rhythm & Timing": [UzuPattern.Pattern.Rhythm],
        Structure: [UzuPattern.Pattern.Structure]
      ],
      authors: ["Ryan Messner"]
    ]
  end
end
