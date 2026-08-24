defmodule ShadowOpsCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :shadowops_core,
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
      extra_applications: [:logger, :runtime_tools, :inets, :ssl],
      mod: {ShadowOpsCore.Application, []}
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.14"},
      {:postgrex, ">= 0.0.0"},
      {:oban, "~> 2.23"},
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.12"}
    ]
  end
end
