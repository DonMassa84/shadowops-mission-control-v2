defmodule ShadowOpsCore.Truthfulness do
  @moduledoc """
  Evidence-backed readiness rules shared by ShadowOps projections.

  A record is never promoted to READY merely because a source supplied a positive
  status string. When evidence fields are present they are authoritative:
  real_data must be true, synthetic must be false, and reachable must be true.
  """

  alias ShadowOpsCore.Status

  @spec ready?(map()) :: boolean()
  def ready?(record) when is_map(record) do
    positive_state?(record) and
      evidence_true_or_absent?(record, :real_data) and
      evidence_false_or_absent?(record, :synthetic) and
      evidence_true_or_absent?(record, :reachable)
  end

  def ready?(_), do: false

  @spec normalize_ready_state(map(), String.t(), String.t()) :: String.t()
  def normalize_ready_state(record, ready_state \\ "READY", fallback_state \\ "NOT_CONFIGURED") do
    if ready?(record), do: ready_state, else: fallback_state
  end

  @spec validate(map()) :: :ok | {:error, atom()}
  def validate(record) when is_map(record) do
    cond do
      positive_state?(record) and has_key?(record, :real_data) and value(record, :real_data) != true ->
        {:error, :positive_without_real_data}

      positive_state?(record) and has_key?(record, :synthetic) and value(record, :synthetic) != false ->
        {:error, :positive_with_synthetic_data}

      positive_state?(record) and has_key?(record, :reachable) and value(record, :reachable) != true ->
        {:error, :positive_without_reachability}

      true ->
        :ok
    end
  end

  def validate(_), do: {:error, :invalid_record}

  defp positive_state?(record) do
    record
    |> state_value()
    |> Status.positive?()
  end

  defp state_value(record) do
    value(record, :status) || value(record, :state) || value(record, :availability) || "UNKNOWN"
  end

  defp evidence_true_or_absent?(record, key), do: not has_key?(record, key) or value(record, key) == true
  defp evidence_false_or_absent?(record, key), do: not has_key?(record, key) or value(record, key) == false

  defp has_key?(record, key), do: Map.has_key?(record, key) or Map.has_key?(record, to_string(key))

  defp value(record, key), do: Map.get(record, key, Map.get(record, to_string(key)))
end
