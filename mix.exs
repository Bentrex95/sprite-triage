defmodule SpriteTriage.MixProject do
  use Mix.Project

  def project do
    [
      app: :sprite_triage,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [sprite_triage: []]
    ]
  end

  def application do
    [mod: {SpriteTriage.Application, []}, extra_applications: [:logger, :crypto]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:sprites, "~> 0.2.4"},
      {:req, "~> 0.5"},
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.2"},
      {:phoenix_html, "~> 4.3"},
      {:bandit, "~> 1.8"},
      {:jason, "~> 1.4"},
      {:lazy_html, ">= 0.0.0", only: :test}
    ]
  end
end
