defmodule WorkflowEngine.MixProject do
  use Mix.Project

  def project do
    [
      app: :workflow_engine,
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
      extra_applications: [:logger],
      mod: {WorkflowEngine.Application, []}
    ]
  end

  defp deps do
    [
      {:yaml_elixir, "~> 2.12"},
      {:shadowops_core, in_umbrella: true}
    ]
  end
end
