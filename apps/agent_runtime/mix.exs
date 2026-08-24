defmodule AgentRuntime.MixProject do
  use Mix.Project

  def project do
    [
      app: :agent_runtime,
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
      mod: {AgentRuntime.Application, []}
    ]
  end

  defp deps do
    [
      {:workflow_engine, in_umbrella: true},
      {:shadowops_core, in_umbrella: true},
      {:jason, "~> 1.4"}
    ]
  end
end
