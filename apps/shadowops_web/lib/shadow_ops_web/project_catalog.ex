defmodule ShadowOpsWeb.ProjectCatalog do
  @moduledoc """
  Web adapter for the canonical local federated project catalog.

  Parsing, sanitization, status normalization, and truthfulness rules live in
  `ShadowOpsCore.ProjectCatalog`; this module only resolves the runtime path.
  """

  alias ShadowOpsCore.ProjectCatalog, as: CoreProjectCatalog
  alias ShadowOpsWeb.ProjectDomains

  def snapshot do
    path = System.get_env("SHADOWOPS_PROJECT_CATALOG") || CoreProjectCatalog.default_path()

    path
    |> CoreProjectCatalog.snapshot()
    |> CoreProjectCatalog.correlate_project(
      "ihk:zero-trust-project",
      ProjectDomains.snapshot(:ihk)
    )
  end
end
