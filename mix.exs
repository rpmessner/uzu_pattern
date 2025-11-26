defmodule UzuPattern.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/rpmessner/uzu_pattern"

  def project do
    [
      app: :uzu_pattern,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "UzuPattern",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:uzu_parser, path: "../uzu_parser"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Pattern orchestration library for Strudel.js-style transformations.
    Provides fast, slow, rev, stack, cat, every, jux and more.
    Works with UzuParser for mini-notation parsing.
    """
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
      extras: ["README.md", "ROADMAP.md", "HANDOFF.md"]
    ]
  end
end
