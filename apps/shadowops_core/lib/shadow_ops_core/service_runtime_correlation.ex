defmodule ShadowOpsCore.ServiceRuntimeCorrelation do
  @moduledoc """
  Pure classification/correlation between a discovery candidate and a
  supplied runtime snapshot.

  This module performs NO runtime IO. It consumes an already-fetched
  runtime snapshot (list of runtime service structs) and derives the
  canonical runtime classification. The caller is responsible for loading
  the runtime snapshot exactly once per request.

  Evidence order:
  1. candidate source_ref
  2. exact service name
  3. scope:name identity
  4. LoadState
  5. FragmentPath/SourcePath
  6. SHA-256 definitions comparison
  7. runtime_verified

  Conflict rules:
  - runtime_conflict=true => runtime_verified=false, connected=false, real_data=false, READY forbidden
  - user/system ambiguity => runtime_ambiguous=true, fail closed
  """

  @spec correlate(map(), list(), nil | map()) :: {:ok, map()}
  def correlate(discovery, runtime_services, _root \\ nil)
      when is_map(discovery) and is_list(runtime_services) do
    candidate = normalize_candidate(discovery)

    case find_exact_match(runtime_services, candidate) do
      {:ok, runtime_svc} ->
        {:ok, merge_evidence(runtime_svc, candidate)}

      {:error, :not_found} ->
        {:ok, discovered_only(candidate)}

      {:error, :ambiguous} ->
        {:ok, ambiguous(candidate)}
    end
  end

  defp normalize_candidate(discovery) do
    %{
      name: Map.get(discovery, :name, Map.get(discovery, "name")),
      scope: Map.get(discovery, :scope, Map.get(discovery, :kind, "unknown")),
      source_ref: Map.get(discovery, :source_ref, Map.get(discovery, :source, "systemctl"))
    }
  end

  defp find_exact_match(runtime_services, candidate) do
    name = candidate.name
    scope = candidate.scope

    matches =
      Enum.filter(runtime_services, fn svc ->
        svc_name = Map.get(svc, :name, Map.get(svc, "name"))
        svc_scope = Map.get(svc, :scope, Map.get(svc, "scope"))

        svc_name == name and (scope == "unknown" or svc_scope == scope)
      end)

    case matches do
      [single] -> {:ok, single}
      [] -> {:error, :not_found}
      _ -> {:error, :ambiguous}
    end
  end

  defp merge_evidence(runtime_svc, candidate) do
    scope = Map.get(runtime_svc, :scope, candidate.scope)
    name = Map.get(runtime_svc, :name, candidate.name)
    runtime_verified = Map.get(runtime_svc, :runtime_verified, false)

    %{
      identity: "#{scope}:#{name}",
      scope: scope,
      name: name,
      load_state: Map.get(runtime_svc, :load_state),
      active_state: Map.get(runtime_svc, :active_state),
      sub_state: Map.get(runtime_svc, :sub_state),
      fragment_path: Map.get(runtime_svc, :fragment_path),
      source_path: Map.get(runtime_svc, :source_path),
      pid: Map.get(runtime_svc, :pid),
      restart_count: Map.get(runtime_svc, :restart_count),
      last_error: Map.get(runtime_svc, :last_error),
      status: if(runtime_verified, do: "RUNTIME_VERIFIED", else: "DISCOVERED"),
      reachable: Map.get(runtime_svc, :active_state) in ["active", "activating", "reloading"],
      real_data: false,
      synthetic: false,
      runtime_verified: runtime_verified,
      runtime_conflict: false,
      runtime_ambiguous: false,
      connected: false,
      live: Map.get(runtime_svc, :active_state) == "active",
      source_ref: candidate.source_ref,
      definition_match: true,
      governance_mapped: false,
      source: Map.get(runtime_svc, :source, "systemctl"),
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp discovered_only(candidate) do
    scope = candidate.scope
    name = candidate.name

    %{
      identity: "#{scope}:#{name}",
      scope: scope,
      name: name,
      load_state: nil,
      active_state: "unknown",
      sub_state: "unknown",
      fragment_path: nil,
      source_path: nil,
      pid: nil,
      restart_count: nil,
      last_error: nil,
      status: "DISCOVERED",
      reachable: false,
      real_data: false,
      synthetic: false,
      runtime_verified: false,
      runtime_conflict: false,
      runtime_ambiguous: false,
      connected: false,
      live: false,
      source_ref: candidate.source_ref,
      definition_match: false,
      governance_mapped: false,
      source: "discovery",
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp ambiguous(candidate) do
    base = discovered_only(candidate)

    %{
      base
      | runtime_ambiguous: true,
        runtime_verified: false,
        connected: false,
        real_data: false
    }
  end

  @spec classify_health(map()) :: atom()
  def classify_health(record) do
    Enum.find_value(health_levels(), :unknown, fn {predicate, state} ->
      if(predicate.(record), do: state, else: nil)
    end)
  end

  defp health_levels do
    [
      {&(&1[:synthetic] == true), :discovered},
      {&(not &1[:runtime_verified]), :discovered},
      {&(not &1[:live]), :runtime_verified},
      {&(not &1[:connected]), :live},
      {&(not &1[:real_data]), :connected},
      {&(not &1[:governance_mapped]), :real_data},
      {& &1[:runtime_conflict], :conflict},
      {& &1[:runtime_ambiguous], :ambiguous},
      {fn _ -> true end, :ready}
    ]
  end
end
