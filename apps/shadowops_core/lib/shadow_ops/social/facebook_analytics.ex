defmodule ShadowOps.Social.FacebookAnalytics do
  @moduledoc """
  Privacy-safe reader for the local Facebook ranking reconstruction.

  This context deliberately exposes only aggregate evidence metadata.  It never
  returns source match text, identity data, messages, or credentials.
  """

  alias ShadowOps.Social.FacebookAnalytics.PrivacyGuard

  @default_source "/home/schattenmacher/ProofFlow-Obsidian-Vault/30_Analytics/Facebook/facebook_ranking_deep.json"
  @source_env "SHADOWOPS_FACEBOOK_ANALYTICS_SOURCE"
  @dimension_keys ~w(volume initiation reply_response latency follow_up reciprocity balance consistency score_weight threshold_class ranking)
  @supported_now ~w(SOURCE_STATUS EVIDENCE_QUALITY AGGREGATE_RANKING_EVIDENCE DIMENSION_STATUS THRESHOLD_EVIDENCE FORMULA_EVIDENCE)
  @unsupported_now ~w(RECIPROCITY_RATIO INITIATION_BALANCE RESPONSE_RATE RESPONSE_LATENCY FOLLOW_UP_RATIO CONSISTENCY DORMANT_CONTACTS REENGAGED_CONTACTS ONE_SIDED_CONTACTS CONTACT_RANKING HISTORICAL_TRENDS FULL_SOCIAL_HEALTH_SCORE)

  @signal_dimensions %{
    "Interaction Volume" => "volume",
    "Message Volume" => "volume",
    "Initiation" => "initiation",
    "Reply" => "reply_response",
    "Response" => "reply_response",
    "Response Latency" => "latency",
    "Follow-ups" => "follow_up",
    "Reciprocity" => "reciprocity",
    "Balance" => "balance",
    "Score" => "score_weight",
    "Weight" => "score_weight",
    "Threshold" => "threshold_class",
    "Classification" => "threshold_class",
    "Ranking" => "ranking"
  }

  def source_path do
    case Application.fetch_env(:shadowops_core, :facebook_analytics_source) do
      {:ok, path} when is_binary(path) and path != "" -> path
      _ -> nonempty_env(@source_env) || @default_source
    end
  end

  def load(path \\ source_path()) do
    case File.read(path) do
      {:ok, body} -> decode(body, path)
      {:error, :enoent} -> {:ok, unavailable(path, :missing)}
      {:error, reason} -> {:ok, unavailable(path, {:source_unreadable, reason})}
    end
  end

  def social_review, do: social_review(source_path())

  def social_review(path) do
    {:ok, analytics} = load(path)

    %{
      source_status: %{
        status: if(analytics.available?, do: "AVAILABLE", else: "UNAVAILABLE"),
        generated_at: analytics.generated_at,
        privacy_status: analytics.privacy_status,
        data_quality: analytics.data_quality
      },
      evidence_quality: evidence_quality(analytics),
      reciprocity: dimension_review(analytics, "reciprocity"),
      initiation: dimension_review(analytics, "initiation"),
      response: dimension_review(analytics, "reply_response"),
      latency: dimension_review(analytics, "latency"),
      follow_up: dimension_review(analytics, "follow_up"),
      consistency: dimension_review(analytics, "consistency"),
      balance: dimension_review(analytics, "balance"),
      contact_distribution:
        availability_review(analytics.available? and analytics.contact_distribution_available),
      trend: availability_review(analytics.available? and analytics.history_available),
      weekly_social_review: %{status: "UNAVAILABLE", active?: false},
      capabilities: %{supported_now: @supported_now, unsupported_now: @unsupported_now}
    }
  end

  def changed?(path, previous_mtime), do: mtime(path) != previous_mtime

  defp decode(body, path) do
    case Jason.decode(body) do
      {:ok, decoded} ->
        case validate(decoded) do
          :ok ->
            sanitized = PrivacyGuard.sanitize(decoded)
            # Formula extraction happens before match text is removed. Only expressions
            # that match the narrow verified allowlist below ever cross this boundary.
            {:ok, build_view(sanitized, path, formulas(decoded["evidence"]))}

          {:error, reason} ->
            {:ok, unavailable(path, reason, true)}
        end

      {:error, %Jason.DecodeError{}} ->
        {:ok, unavailable(path, :invalid_json, false)}
    end
  end

  defp validate(%{"evidence" => evidence, "dimension_status" => statuses, "buckets" => buckets})
       when is_list(evidence) and is_map(statuses) and is_list(buckets),
       do: :ok

  defp validate(_), do: {:error, :invalid_schema}

  defp build_view(data, path, verified_formulas) do
    evidence = data["evidence"] |> Enum.filter(&is_map/1) |> Enum.map(&evidence_view/1)
    thresholds = data["buckets"] |> Enum.filter(&is_map/1) |> Enum.flat_map(&threshold_views/1)
    formulas = verified_formulas
    statuses = dimension_statuses(data["dimension_status"])
    contact_distribution_available = nonempty_list?(data["contact_distribution"])
    history_available = history_available?(data)

    %{
      available?: true,
      source: source_view(path),
      generated_at: data["generated_at"],
      json_valid: true,
      privacy_status: "PROTECTED",
      data_quality: data_quality(statuses, contact_distribution_available, history_available),
      pipeline_status: "AVAILABLE",
      ranking_engine_status: if(formulas == [], do: "PARTIAL", else: "VERIFIED_FROM_CODE"),
      metrics: Map.new(kpi_names(), &{&1, nil}),
      formulas: formulas,
      thresholds: thresholds,
      signals: signal_views(statuses),
      dimension_status: statuses,
      evidence: evidence,
      evidence_count: length(evidence),
      bucket_count: length(data["buckets"]),
      contact_distribution: [],
      contact_distribution_available: contact_distribution_available,
      history_available: history_available,
      multidimensional_status: "NOT_VERIFIED"
    }
  end

  defp unavailable(path, reason, json_valid \\ false) do
    %{
      available?: false,
      source: source_view(path),
      generated_at: nil,
      json_valid: json_valid,
      unavailable_reason: reason,
      privacy_status: "PROTECTED",
      data_quality: "UNAVAILABLE",
      pipeline_status: "NOT_AVAILABLE",
      ranking_engine_status: "NOT_AVAILABLE",
      metrics: Map.new(kpi_names(), &{&1, nil}),
      formulas: [],
      thresholds: [],
      signals: signal_views(%{}),
      dimension_status: %{},
      evidence: [],
      evidence_count: nil,
      bucket_count: nil,
      contact_distribution: [],
      contact_distribution_available: false,
      history_available: false,
      multidimensional_status: "NOT_VERIFIED"
    }
  end

  defp source_view(path), do: %{path: path, mtime: mtime(path), sha256: sha256(path)}

  defp mtime(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.mtime
      _ -> nil
    end
  end

  defp sha256(path) do
    case File.read(path) do
      {:ok, body} -> :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
      _ -> nil
    end
  end

  defp evidence_view(item) do
    %{
      finding: item["dimensions"] |> safe_list() |> Enum.join(", "),
      status:
        if(item["priority"] == true, do: "VERIFIED_FROM_CODE", else: "INFERRED_FROM_REPORT"),
      file: item["path"],
      line: item["matches"] |> safe_list() |> List.first() |> then(&(&1 && &1["line"])),
      sha256: item["sha256"]
    }
  end

  defp threshold_views(bucket) do
    bucket["chain"]
    |> safe_list()
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn item ->
      %{
        condition: item["condition"],
        classification: item["class"],
        file: bucket["path"],
        line: item["line"],
        sha256: bucket["sha256"]
      }
    end)
  end

  defp formulas(evidence) do
    evidence
    |> safe_list()
    |> Enum.filter(&is_map/1)
    |> Enum.filter(&(&1["priority"] == true))
    |> Enum.flat_map(fn item ->
      item["matches"]
      |> safe_list()
      |> Enum.filter(&is_map/1)
      |> Enum.flat_map(fn match ->
        formula_from(match["text"], item, match["line"])
      end)
    end)
    |> Enum.uniq_by(& &1.name)
  end

  defp formula_from(text, item, line) when is_binary(text) do
    normalized = String.replace(text, ~r/\s+/, " ")

    cond do
      Regex.match?(~r/power_score\s*=\s*interactions\s*\/\s*1000/, normalized) ->
        [formula("power_score", "interactions / 1000", item, line)]

      Regex.match?(~r/risk_score.*interactions.*\/\s*1000\s*\*\s*2/, normalized) ->
        [formula("risk_score", "(interactions / 1000) * 2", item, line)]

      true ->
        []
    end
  end

  defp formula_from(_, _, _), do: []

  defp formula(name, expression, item, line),
    do: %{
      name: name,
      expression: expression,
      status: "VERIFIED_FROM_CODE",
      file: item["path"],
      line: line,
      sha256: item["sha256"]
    }

  defp signal_views(statuses) do
    @signal_dimensions
    |> Map.new(fn {label, key} ->
      source_status = Map.get(statuses, key)
      {label, %{status: signal_status(source_status), source_dimension: key}}
    end)
  end

  defp signal_status("VERIFIED"), do: "VERIFIED_FROM_CODE"
  defp signal_status("PARTIAL"), do: "PARTIAL"
  defp signal_status(_), do: "NOT_FOUND"

  defp dimension_statuses(statuses) when is_map(statuses) do
    statuses
    |> Map.take(@dimension_keys)
    |> Map.new(fn {key, value} ->
      status = if is_map(value), do: value["status"], else: value
      {key, if(status in ~w(VERIFIED PARTIAL MISSING), do: status, else: "MISSING")}
    end)
  end

  defp dimension_statuses(_), do: %{}

  defp evidence_quality(analytics) do
    statuses = analytics.dimension_status

    %{
      source_available: analytics.available?,
      json_valid: analytics.json_valid,
      generated_at_present: is_binary(analytics.generated_at) and analytics.generated_at != "",
      evidence_count: analytics.evidence_count,
      bucket_count: analytics.bucket_count,
      dimension_verified_count: count_status(statuses, "VERIFIED", analytics.available?),
      dimension_partial_count: count_status(statuses, "PARTIAL", analytics.available?),
      dimension_missing_count: count_status(statuses, "MISSING", analytics.available?),
      contact_distribution_available: analytics.contact_distribution_available
    }
  end

  defp count_status(_statuses, _status, false), do: nil

  defp count_status(statuses, status, true),
    do: Enum.count(statuses, fn {_key, value} -> value == status end)

  defp dimension_review(%{available?: false}, _key), do: %{status: "UNAVAILABLE"}

  defp dimension_review(analytics, key) do
    case analytics.dimension_status[key] do
      "VERIFIED" -> %{status: "VERIFIED"}
      "PARTIAL" -> %{status: "PARTIAL"}
      _ -> %{status: "UNAVAILABLE"}
    end
  end

  defp availability_review(true), do: %{status: "AVAILABLE"}
  defp availability_review(false), do: %{status: "UNAVAILABLE"}

  defp data_quality(statuses, contact_distribution_available, history_available) do
    if map_size(statuses) > 0 and
         Enum.all?(statuses, fn {_key, status} -> status == "VERIFIED" end) and
         contact_distribution_available and history_available,
       do: "VERIFIED",
       else: "PARTIAL"
  end

  defp nonempty_list?(value), do: is_list(value) and value != []

  defp history_available?(data) do
    Enum.any?(~w(history historical snapshots), &nonempty_list?(data[&1]))
  end

  defp safe_list(value) when is_list(value), do: value
  defp safe_list(_), do: []

  defp nonempty_env(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp kpi_names,
    do: [
      "TOTAL EVENTS",
      "TOTAL CHATS",
      "1:1 CHATS",
      "TOTAL MESSAGES",
      "OUTBOUND",
      "INBOUND",
      "RECIPROCITY",
      "INITIATION RATE",
      "RESPONSE LATENCY ME",
      "RESPONSE LATENCY OTHER",
      "FOLLOW-UPS ME",
      "FOLLOW-UPS OTHER"
    ]
end
