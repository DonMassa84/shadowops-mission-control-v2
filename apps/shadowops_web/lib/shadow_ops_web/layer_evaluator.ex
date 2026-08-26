defmodule ShadowOpsWeb.LayerEvaluator do
  @moduledoc """
  Deterministic, read-only health projection for the standalone Mission Control.

  Only evidence exposed by `RuntimeOverview` is scored. Layers whose canonical
  evidence is not implemented in this repository are reported as
  `NOT_ASSESSED`; missing evidence is never converted into a fabricated zero.
  """

  alias ShadowOpsWeb.RuntimeOverview

  @layer_order ~w(sources data_fabric data_quality lineage ontology identity relationships projects workflows runtime governance knowledge)

  @weights %{
    "sources" => 1.0,
    "data_fabric" => 1.2,
    "data_quality" => 1.0,
    "lineage" => 1.2,
    "ontology" => 1.1,
    "identity" => 1.0,
    "relationships" => 1.0,
    "projects" => 0.9,
    "workflows" => 1.0,
    "runtime" => 1.0,
    "governance" => 1.3,
    "knowledge" => 0.8
  }

  @positive ~w(PASS VALID AVAILABLE CONNECTED ONLINE SUCCESS APPROVED READY VERIFIED HEALTHY ACTIVE)
  @review ~w(PENDING RUNNING QUEUED DEGRADED PARTIAL REVIEW WARN WARNING)
  @negative ~w(FAIL INVALID ERROR OFFLINE FAILED REJECTED BLOCKED BLOCKED_CONFIGURATION CRITICAL)

  def snapshot, do: build_snapshot()

  def layer(id) when is_binary(id) do
    case Enum.find(snapshot().layers, &(&1.id == id)) do
      nil -> {:error, :not_found}
      layer -> {:ok, layer}
    end
  end

  def layer(_), do: {:error, :not_found}

  @doc false
  def build_snapshot do
    runtime = RuntimeOverview.snapshot()

    layers =
      [
        probe_layer("sources", "Sources", Map.get(runtime, :connectors), "runtime connectors"),
        not_assessed(
          "data_fabric",
          "Data Fabric",
          "Canonical Data Fabric projection is not implemented in this standalone repository."
        ),
        not_assessed(
          "data_quality",
          "Data Quality",
          "Canonical record-quality evidence is not implemented in this standalone repository."
        ),
        not_assessed(
          "lineage",
          "Lineage",
          "Canonical lineage projection is not implemented in this standalone repository."
        ),
        not_assessed(
          "ontology",
          "Ontology",
          "Ontology projection is not implemented in this standalone repository."
        ),
        not_assessed(
          "identity",
          "Identity",
          "Canonical identity-resolution evidence is not implemented in this standalone repository."
        ),
        not_assessed(
          "relationships",
          "Relationships",
          "Evidence-backed relationship graph is not implemented in this standalone repository."
        ),
        not_assessed(
          "projects",
          "Projects",
          "Canonical Project-object evidence is not implemented in this standalone repository."
        ),
        probe_layer("workflows", "Workflows", Map.get(runtime, :workflows), "workflow registry"),
        runtime_layer(runtime),
        governance_layer(runtime),
        probe_layer("knowledge", "Knowledge", Map.get(runtime, :knowledge), "knowledge runtime")
      ]
      |> sort_layers()

    assessed = Enum.filter(layers, & &1.assessed)
    findings = layers |> Enum.flat_map(& &1.findings) |> sort_findings()
    score = weighted_average(assessed)
    state = if critical?(findings), do: "CRITICAL", else: state_for_score(score)

    %{
      id: "layer-health",
      status: state,
      state: state,
      score: score,
      assessed_layers: length(assessed),
      total_layers: length(layers),
      overall_coverage: ratio(length(assessed), length(layers)),
      critical_findings: Enum.count(findings, &(&1.severity == "CRITICAL")),
      warnings: Enum.count(findings, &(&1.severity == "WARN")),
      generated_at: now(),
      real_data: true,
      synthetic: false,
      layers: layers,
      findings: findings
    }
  end

  defp runtime_layer(runtime) do
    probes = [
      Map.get(runtime, :system),
      Map.get(runtime, :services),
      Map.get(runtime, :nodes),
      Map.get(runtime, :readiness)
    ]

    aggregate_layer("runtime", "Runtime", probes, "bounded runtime probes")
  end

  defp governance_layer(runtime) do
    probes = [Map.get(runtime, :security), Map.get(runtime, :audit)]

    case aggregate_layer("governance", "Governance", probes, "security and audit evidence") do
      %{assessed: false} = layer ->
        layer

      layer ->
        critical =
          probes
          |> Enum.filter(&evidence?/1)
          |> Enum.any?(fn probe -> normalize_status(probe) in @negative end)

        if critical do
          finding =
            finding(
              "GOVERNANCE_CONTROL_FAILURE",
              "CRITICAL",
              "Security or audit evidence reports a failing control.",
              "governance"
            )

          %{
            layer
            | state: "CRITICAL",
              score: min(layer.score || 0, 49),
              failures: layer.failures + 1,
              findings: sort_findings([finding | layer.findings])
          }
        else
          layer
        end
    end
  end

  defp aggregate_layer(id, name, probes, source) do
    present = Enum.filter(probes, &evidence?/1)

    if present == [] do
      not_assessed(id, name, "No #{source} is currently available.")
    else
      scores = Enum.map(present, &probe_score/1)
      score = round(Enum.sum(scores) / length(scores))
      states = Enum.map(present, &normalize_status/1)
      failures = Enum.count(states, &(&1 in @negative))
      warnings = Enum.count(states, &(&1 in @review))

      findings =
        []
        |> maybe_add(
          failures > 0,
          "#{String.upcase(id)}_FAILURE",
          "CRITICAL",
          "#{failures} #{source} probe(s) report failure.",
          id
        )
        |> maybe_add(
          warnings > 0,
          "#{String.upcase(id)}_REVIEW",
          "WARN",
          "#{warnings} #{source} probe(s) require review.",
          id
        )

      result(id, name, score, ratio(length(present), length(probes)), findings, %{
        source: source,
        evidenced_probes: length(present),
        total_probes: length(probes)
      })
    end
  end

  defp probe_layer(id, name, probe, source) do
    if evidence?(probe) do
      status = normalize_status(probe)
      score = probe_score(probe)

      findings =
        []
        |> maybe_add(
          status in @negative,
          "#{String.upcase(id)}_FAILURE",
          "CRITICAL",
          "#{name} evidence reports #{status}.",
          id
        )
        |> maybe_add(
          status in @review,
          "#{String.upcase(id)}_REVIEW",
          "WARN",
          "#{name} evidence reports #{status}.",
          id
        )

      result(id, name, score, 1.0, findings, %{
        source: source,
        status: status,
        records: record_count(probe)
      })
    else
      not_assessed(id, name, "No #{source} evidence is currently available.")
    end
  end

  defp evidence?(probe) when is_map(probe) do
    availability = probe |> value(:availability) |> normalize()
    status = normalize_status(probe)

    availability not in ["", "UNAVAILABLE", "NOT_CONFIGURED", "NOT_CONNECTED", "UNKNOWN"] and
      status not in ["", "UNAVAILABLE", "NOT_CONFIGURED", "NOT_CONNECTED", "UNKNOWN"]
  end

  defp evidence?(_), do: false

  defp probe_score(probe) do
    case normalize_status(probe) do
      status when status in @positive -> 100
      status when status in @review -> 70
      status when status in @negative -> 20
      _ -> 50
    end
  end

  defp normalize_status(probe) when is_map(probe) do
    [:state, :status, :health, :overall, :availability]
    |> Enum.map(&(probe |> value(&1) |> normalize()))
    |> Enum.find("UNKNOWN", &(&1 not in ["", "UNKNOWN", "AVAILABLE"]))
    |> case do
      "UNKNOWN" -> probe |> value(:availability) |> normalize()
      value -> value
    end
  end

  defp normalize_status(_), do: "UNKNOWN"

  defp record_count(probe) when is_map(probe) do
    cond do
      is_integer(value(probe, :record_count)) -> value(probe, :record_count)
      is_integer(value(probe, :count)) -> value(probe, :count)
      is_list(value(probe, :records)) -> length(value(probe, :records))
      true -> nil
    end
  end

  defp result(id, name, score, coverage, findings, metrics) do
    state =
      if Enum.any?(findings, &(&1.severity == "CRITICAL")),
        do: "CRITICAL",
        else: state_for_score(score)

    %{
      id: id,
      name: name,
      score: score,
      state: state,
      assessed: true,
      coverage: coverage,
      warnings: Enum.count(findings, &(&1.severity == "WARN")),
      failures: Enum.count(findings, &(&1.severity == "CRITICAL")),
      findings: sort_findings(findings),
      metrics: metrics,
      updated_at: now()
    }
  end

  defp not_assessed(id, name, reason) do
    finding = finding("EVIDENCE_NOT_AVAILABLE", "INFO", reason, id)

    %{
      id: id,
      name: name,
      score: nil,
      state: "NOT_ASSESSED",
      assessed: false,
      coverage: nil,
      warnings: 0,
      failures: 0,
      findings: [finding],
      metrics: %{},
      updated_at: now()
    }
  end

  defp finding(code, severity, message, layer_id),
    do: %{code: code, severity: severity, message: message, layer_id: layer_id}

  defp maybe_add(findings, true, code, severity, message, layer_id),
    do: [finding(code, severity, message, layer_id) | findings]

  defp maybe_add(findings, false, _code, _severity, _message, _layer_id), do: findings

  defp weighted_average([]), do: nil

  defp weighted_average(layers) do
    {weighted, weight} =
      Enum.reduce(layers, {0.0, 0.0}, fn layer, {sum, total} ->
        layer_weight = Map.fetch!(@weights, layer.id)
        {sum + layer.score * layer_weight, total + layer_weight}
      end)

    round(weighted / weight)
  end

  defp state_for_score(nil), do: "NOT_ASSESSED"
  defp state_for_score(score) when score >= 95, do: "EXCELLENT"
  defp state_for_score(score) when score >= 85, do: "HEALTHY"
  defp state_for_score(score) when score >= 70, do: "REVIEW"
  defp state_for_score(score) when score >= 50, do: "DEGRADED"
  defp state_for_score(_score), do: "CRITICAL"

  defp critical?(findings), do: Enum.any?(findings, &(&1.severity == "CRITICAL"))

  defp sort_layers(layers) do
    order = @layer_order |> Enum.with_index() |> Map.new()
    Enum.sort_by(layers, &Map.fetch!(order, &1.id))
  end

  defp sort_findings(findings) do
    priority = %{"CRITICAL" => 0, "WARN" => 1, "INFO" => 2}
    Enum.sort_by(findings, &{Map.get(priority, &1.severity, 9), &1.layer_id, &1.code})
  end

  defp ratio(_value, 0), do: nil
  defp ratio(value, total), do: value / total

  defp value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))

  defp normalize(nil), do: ""
  defp normalize(value) when is_atom(value), do: value |> Atom.to_string() |> String.upcase()
  defp normalize(value) when is_binary(value), do: String.upcase(value)
  defp normalize(value), do: value |> to_string() |> String.upcase()

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
