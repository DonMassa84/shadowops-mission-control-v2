defmodule ShadowOpsWeb.PrometheusExporter do
  @moduledoc "Minimal dependency-free Prometheus projection for ShadowOps control-plane state."

  alias ShadowOpsWeb.IntegrationCatalog

  def render do
    catalog = IntegrationCatalog.snapshot()

    header = [
      "# HELP shadowops_integrations_total Number of integration catalog records.",
      "# TYPE shadowops_integrations_total gauge",
      "shadowops_integrations_total #{catalog.record_count}",
      "# HELP shadowops_integrations_positive Number of evidence-backed positive integration states.",
      "# TYPE shadowops_integrations_positive gauge",
      "shadowops_integrations_positive #{catalog.positive_count}",
      "# HELP shadowops_integrations_core Number of core ShadowOps integration records.",
      "# TYPE shadowops_integrations_core gauge",
      "shadowops_integrations_core #{catalog.core_count}",
      "# HELP shadowops_integrations_external Number of detected external connector records.",
      "# TYPE shadowops_integrations_external gauge",
      "shadowops_integrations_external #{catalog.external_count}",
      "# HELP shadowops_integration_status Evidence-backed integration status as a labeled gauge.",
      "# TYPE shadowops_integration_status gauge"
    ]

    status_lines =
      Enum.map(catalog.records, fn item ->
        labels =
          [
            {"id", item.id},
            {"name", item.name},
            {"scope", item.scope},
            {"kind", item.kind},
            {"status", item.status},
            {"health", item.health},
            {"source_type", item.source_type}
          ]
          |> Enum.map_join(",", fn {key, value} -> ~s(#{key}="#{escape(value)}") end)

        "shadowops_integration_status{#{labels}} 1"
      end)

    truth_lines =
      [
        "# HELP shadowops_integration_real_data Whether an integration state is backed by real data.",
        "# TYPE shadowops_integration_real_data gauge"
      ] ++
        Enum.map(catalog.records, fn item ->
          ~s(shadowops_integration_real_data{id="#{escape(item.id)}"} #{bool(item.real_data)})
        end) ++
        [
          "# HELP shadowops_integration_reachable Whether the integration source is currently reachable.",
          "# TYPE shadowops_integration_reachable gauge"
        ] ++
        Enum.map(catalog.records, fn item ->
          ~s(shadowops_integration_reachable{id="#{escape(item.id)}"} #{bool(item.reachable)})
        end) ++
        [
          "# HELP shadowops_integration_synthetic Whether an integration state is synthetic. Production positive states must remain zero.",
          "# TYPE shadowops_integration_synthetic gauge"
        ] ++
        Enum.map(catalog.records, fn item ->
          ~s(shadowops_integration_synthetic{id="#{escape(item.id)}"} #{bool(item.synthetic)})
        end)

    Enum.join(header ++ status_lines ++ truth_lines, "\n") <> "\n"
  end

  defp bool(true), do: 1
  defp bool(_), do: 0

  defp escape(nil), do: ""

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\n", "\\n")
    |> String.replace("\"", "\\\"")
  end
end
