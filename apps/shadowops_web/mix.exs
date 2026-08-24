defmodule ShadowOpsWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :shadowops_web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: ">= 1.17.0 and < 2.0.0",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {ShadowOpsWeb.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      {:phoenix_live_view, "~> 1.2.7"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:bandit, "~> 1.12"},
      {:jason, "~> 1.4"},
      {:workflow_engine, in_umbrella: true},
      {:shadowops_core, in_umbrella: true}
    ]
  end
end
