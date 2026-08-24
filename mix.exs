defmodule ShadowOps.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      elixir: ">= 1.17.0 and < 2.0.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  defp deps, do: []

  defp aliases do
    ["phx.routes": "phx.routes ShadowOpsWeb.Router"]
  end
end
