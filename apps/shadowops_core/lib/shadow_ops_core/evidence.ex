defmodule ShadowOpsCore.Evidence do
  @moduledoc "Deterministic evidence, trust-score and desired/actual drift evaluation."

  @derive Jason.Encoder
  @enforce_keys [
    :id,
    :resource_id,
    :verified_at,
    :verification_type,
    :result,
    :provenance,
    :checks
  ]
  defstruct [
    :id,
    :resource_id,
    :verified_at,
    :verification_type,
    :result,
    :provenance,
    :checks,
    :trust_score
  ]

  @type t :: %__MODULE__{}

  def build(resource_id, verification_type, checks, provenance)
      when is_binary(resource_id) and is_binary(verification_type) and is_list(checks) and
             is_binary(provenance) do
    normalized = Enum.map(checks, &normalize_check/1)

    if normalized != [] and Enum.all?(normalized, &(&1.result in ["PASS", "FAIL"])) do
      passed = Enum.count(normalized, &(&1.result == "PASS"))
      score = div(passed * 100, length(normalized))

      {:ok,
       %__MODULE__{
         id: "evidence:" <> digest(resource_id <> ":" <> Jason.encode!(normalized)),
         resource_id: resource_id,
         verified_at: DateTime.utc_now(),
         verification_type: verification_type,
         result: if(passed == length(normalized), do: "PASS", else: "FAIL"),
         provenance: provenance,
         checks: normalized,
         trust_score: score
       }}
    else
      {:error, :invalid_evidence_checks}
    end
  end

  def build(_, _, _, _), do: {:error, :invalid_evidence}

  def drift(desired, actual, suggested_action \\ nil, risk \\ "L0") do
    drift? = desired != actual

    %{
      desired: desired,
      actual: actual,
      drift: drift?,
      suggested_action: if(drift?, do: suggested_action, else: nil),
      risk: if(drift?, do: risk, else: "L0"),
      remediation: if(drift?, do: "POLICY_REQUIRED", else: "NONE")
    }
  end

  defp normalize_check(check) when is_map(check) do
    %{
      gate: Map.get(check, :gate) || Map.get(check, "gate"),
      result:
        (Map.get(check, :result) || Map.get(check, "result")) |> to_string() |> String.upcase(),
      evidence_ref: Map.get(check, :evidence_ref) || Map.get(check, "evidence_ref")
    }
  end

  defp normalize_check(_), do: %{gate: nil, result: "INVALID", evidence_ref: nil}
  defp digest(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
