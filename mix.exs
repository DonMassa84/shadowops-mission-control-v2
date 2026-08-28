defmodule ShadowOps.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      elixir: ">= 1.17.0 and < 2.0.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases(),
      dialyzer: [plt_add_apps: [:mix]]
    ]
  end

  defp deps do
    [
      {:credo, "1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "1.4.7", only: [:dev, :test], runtime: false},
      {:sobelow, "0.15.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    ["phx.routes": "phx.routes ShadowOpsWeb.Router"]
  end

  defp releases do
    [
      shadowops: [
        applications: [
          shadowops_core: :permanent,
          workflow_engine: :permanent,
          agent_runtime: :permanent,
          shadowops_web: :permanent
        ],
        include_executables_for: [:unix]
      ]
    ]
  end
end
