defmodule AgentRuntime.ExternalWorkflowSpec do
  @moduledoc "Normalized contract for workflows executed by external runtimes such as TCC."

  alias AgentRuntime.RiskPolicy

  @enforce_keys [:id, :runtime_set, :executor, :risk_level]
  defstruct id: nil,
            runtime_set: nil,
            executor: nil,
            risk_level: nil,
            capability: nil,
            approval_required: nil,
            automatic_execution: nil,
            effect_scope: nil,
            blocker: nil,
            status: :known,
            metadata: %{}

  @type t :: %__MODULE__{}

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    with id when is_binary(id) and byte_size(id) > 0 <- Map.get(attrs, :id),
         runtime_set when is_binary(runtime_set) and byte_size(runtime_set) > 0 <-
           Map.get(attrs, :runtime_set),
         executor when not is_nil(executor) <- Map.get(attrs, :executor),
         risk_level when is_binary(risk_level) <- Map.get(attrs, :risk_level),
         {:ok, policy} <- RiskPolicy.get(risk_level) do
      {:ok,
       struct(
         __MODULE__,
         Map.merge(
           %{
             approval_required: policy.approval_required,
             automatic_execution: policy.automatic_execution,
             effect_scope: policy.effect_scope
           },
           attrs
         )
       )}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_external_workflow_spec}
    end
  rescue
    KeyError -> {:error, :unknown_external_workflow_spec_field}
  end
end
