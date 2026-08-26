defmodule WorkflowEngine.AgentContract do
  @moduledoc """
  Fail-closed validator for the schema-v2 generic workflow agent contract.

  The contract binds a canonical workflow to the existing ShadowOps capability,
  risk, approval and runtime registries. It is metadata-only: it never executes a
  runtime, resolves arbitrary commands, or treats client-provided values as
  authoritative.
  """

  alias ShadowOpsCore.{CapabilityRegistry, RiskPolicy}
  alias WorkflowEngine.Registry.Error

  @version 1
  @required_contract_keys ~w(
    version
    agent_spec
    capabilities
    required_inputs
    produced_outputs
    permissions
    timeout_seconds
    retry_policy
    human_review_policy
    evidence_policy
  )
  @backoff_modes ~w(none fixed exponential)

  @spec validate_registry(map()) :: :ok | {:error, Error.t()}
  def validate_registry(%{"workflows" => workflows, "agent_contracts" => contracts})
      when is_map(workflows) and is_map(contracts) do
    workflow_ids = workflows |> Map.keys() |> Enum.sort()
    contract_ids = contracts |> Map.keys() |> Enum.sort()

    if workflow_ids == contract_ids do
      Enum.reduce_while(workflows, :ok, fn {workflow_id, workflow}, :ok ->
        workflow_with_contract = Map.put(workflow, "agent_contract", contracts[workflow_id])

        case validate(workflow_with_contract, ["workflows", workflow_id]) do
          :ok -> {:cont, :ok}
          {:error, %Error{}} = validation_error -> {:halt, validation_error}
        end
      end)
    else
      error(:agent_contract_workflow_set_mismatch, ["agent_contracts"], %{
        missing_contracts: workflow_ids -- contract_ids,
        unknown_contracts: contract_ids -- workflow_ids
      })
    end
  end

  def validate_registry(%{"workflows" => workflows}) when is_map(workflows) do
    error(:agent_contracts_missing, ["agent_contracts"], %{workflow_count: map_size(workflows)})
  end

  def validate_registry(value) do
    error(:invalid_agent_contract_registry, [], %{actual: type_of(value)})
  end

  @spec validate(map(), [String.t()]) :: :ok | {:error, Error.t()}
  def validate(workflow, base) when is_map(workflow) and is_list(base) do
    case workflow["agent_contract"] do
      contract when is_map(contract) ->
        validate_contract(contract, workflow, base ++ ["agent_contract"])

      value ->
        error(:missing_or_invalid_agent_contract, base ++ ["agent_contract"], %{
          actual: type_of(value)
        })
    end
  end

  defp validate_contract(contract, workflow, base) do
    with :ok <- require_keys(contract, base),
         :ok <- validate_version(contract, base),
         :ok <- validate_string_list(contract, "capabilities", base, false),
         :ok <- validate_string_list(contract, "required_inputs", base, true),
         :ok <- validate_string_list(contract, "produced_outputs", base, false),
         :ok <- validate_string_list(contract, "permissions", base, false),
         :ok <- validate_timeout(contract, base),
         :ok <- validate_retry_policy(contract["retry_policy"], base ++ ["retry_policy"]),
         :ok <-
           validate_agent_spec(
             contract["agent_spec"],
             contract,
             workflow,
             base ++ ["agent_spec"]
           ),
         :ok <-
           validate_human_review(contract["human_review_policy"], contract["agent_spec"], base),
         :ok <- validate_evidence_policy(contract["evidence_policy"], base ++ ["evidence_policy"]) do
      :ok
    end
  end

  defp require_keys(contract, base) do
    missing = Enum.reject(@required_contract_keys, &Map.has_key?(contract, &1))

    case missing do
      [] -> :ok
      keys -> error(:agent_contract_missing_keys, base, %{missing: keys})
    end
  end

  defp validate_version(%{"version" => @version}, _base), do: :ok

  defp validate_version(%{"version" => version}, base) do
    error(:unsupported_agent_contract_version, base ++ ["version"], %{
      actual: version,
      expected: @version
    })
  end

  defp validate_agent_spec(spec, contract, workflow, base) when is_map(spec) do
    with :ok <- require_string(spec, "executor", base),
         :ok <- require_string(spec, "capability", base),
         :ok <- require_string(spec, "risk_level", base),
         :ok <- require_string(spec, "runtime_binding", base),
         :ok <- require_boolean(spec, "approval_required", base),
         :ok <- validate_capability(spec, contract, base),
         :ok <- validate_risk(spec, base),
         :ok <- validate_runtime_binding(spec, workflow, base),
         :ok <- validate_approval(spec, base) do
      :ok
    end
  end

  defp validate_agent_spec(value, _contract, _workflow, base) do
    error(:invalid_agent_spec, base, %{actual: type_of(value)})
  end

  defp validate_capability(spec, contract, base) do
    capability = spec["capability"]
    executor = spec["executor"]
    capabilities = contract["capabilities"]

    with true <- capability in capabilities,
         {:ok, capability_spec} <- CapabilityRegistry.lookup(capability),
         expected_executor <- Atom.to_string(capability_spec.executor),
         true <- executor == expected_executor,
         :ok <- validate_all_capabilities(capabilities, base) do
      :ok
    else
      false ->
        error(:agent_capability_or_executor_mismatch, base, %{
          capability: capability,
          executor: executor,
          declared_capabilities: capabilities
        })

      {:error, {:unknown_capability, unknown}} ->
        error(:unknown_agent_capability, base ++ ["capability"], %{capability: unknown})
    end
  end

  defp validate_all_capabilities(capabilities, base) do
    Enum.reduce_while(capabilities, :ok, fn capability, :ok ->
      case CapabilityRegistry.lookup(capability) do
        {:ok, _spec} ->
          {:cont, :ok}

        {:error, {:unknown_capability, unknown}} ->
          {:halt,
           error(:unknown_agent_capability, base ++ ["capabilities"], %{capability: unknown})}
      end
    end)
  end

  defp validate_risk(spec, base) do
    capability = spec["capability"]
    risk = spec["risk_level"]

    with {:ok, _policy} <- RiskPolicy.get(risk),
         inferred when is_binary(inferred) <- RiskPolicy.infer_risk(capability),
         true <- inferred == risk do
      :ok
    else
      {:error, :unknown_risk_level} ->
        error(:unknown_agent_risk_level, base ++ ["risk_level"], %{risk_level: risk})

      :unknown ->
        error(:unknown_capability_risk, base ++ ["risk_level"], %{capability: capability})

      false ->
        error(:agent_risk_mismatch, base ++ ["risk_level"], %{
          capability: capability,
          declared: risk,
          expected: RiskPolicy.infer_risk(capability)
        })
    end
  end

  defp validate_runtime_binding(spec, workflow, base) do
    declared = spec["runtime_binding"]
    expected = workflow["target_runtime"] || workflow["runtime"]

    if is_binary(expected) and expected != "" and declared == expected do
      :ok
    else
      error(:agent_runtime_binding_mismatch, base ++ ["runtime_binding"], %{
        declared: declared,
        expected: expected
      })
    end
  end

  defp validate_approval(spec, base) do
    risk = spec["risk_level"]
    declared = spec["approval_required"]

    case RiskPolicy.get(risk) do
      {:ok, %{approval_required: expected}} when declared == expected ->
        :ok

      {:ok, %{approval_required: expected}} ->
        error(:agent_approval_policy_mismatch, base ++ ["approval_required"], %{
          declared: declared,
          expected: expected,
          risk_level: risk
        })

      {:error, :unknown_risk_level} ->
        error(:unknown_agent_risk_level, base ++ ["risk_level"], %{risk_level: risk})
    end
  end

  defp validate_human_review(policy, agent_spec, base)
       when is_map(policy) and is_map(agent_spec) do
    review_base = base ++ ["human_review_policy"]

    with :ok <- require_boolean(policy, "required", review_base),
         :ok <- validate_string_list(policy, "triggers", review_base, true),
         {:ok, risk_policy} <- RiskPolicy.get(agent_spec["risk_level"]) do
      if risk_policy.approval_required and policy["required"] != true do
        error(:human_review_required_for_approval, review_base ++ ["required"], %{
          risk_level: agent_spec["risk_level"]
        })
      else
        :ok
      end
    end
  end

  defp validate_human_review(value, _agent_spec, base) do
    error(:invalid_human_review_policy, base ++ ["human_review_policy"], %{
      actual: type_of(value)
    })
  end

  defp validate_evidence_policy(policy, base) when is_map(policy) do
    with :ok <- require_boolean(policy, "required", base),
         :ok <- require_boolean(policy, "audit_required", base),
         :ok <- validate_string_list(policy, "fields", base, false) do
      if policy["required"] == true and policy["audit_required"] == true do
        :ok
      else
        error(:agent_evidence_policy_must_fail_closed, base, %{
          required: policy["required"],
          audit_required: policy["audit_required"]
        })
      end
    end
  end

  defp validate_evidence_policy(value, base) do
    error(:invalid_agent_evidence_policy, base, %{actual: type_of(value)})
  end

  defp validate_retry_policy(policy, base) when is_map(policy) do
    max_attempts = policy["max_attempts"]
    backoff = policy["backoff"]

    cond do
      not (is_integer(max_attempts) and max_attempts >= 1) ->
        error(:invalid_agent_retry_attempts, base ++ ["max_attempts"], %{actual: max_attempts})

      backoff not in @backoff_modes ->
        error(:invalid_agent_retry_backoff, base ++ ["backoff"], %{
          actual: backoff,
          allowed: @backoff_modes
        })

      true ->
        :ok
    end
  end

  defp validate_retry_policy(value, base) do
    error(:invalid_agent_retry_policy, base, %{actual: type_of(value)})
  end

  defp validate_timeout(%{"timeout_seconds" => timeout}, _base)
       when is_integer(timeout) and timeout > 0,
       do: :ok

  defp validate_timeout(%{"timeout_seconds" => timeout}, base) do
    error(:invalid_agent_timeout, base ++ ["timeout_seconds"], %{actual: timeout})
  end

  defp validate_string_list(map, key, base, allow_empty) do
    case map[key] do
      values when is_list(values) ->
        valid_strings = Enum.all?(values, &(is_binary(&1) and byte_size(&1) > 0))
        valid_size = allow_empty or values != []

        if valid_strings and valid_size do
          :ok
        else
          error(:invalid_agent_string_list, base ++ [key], %{
            actual: values,
            allow_empty: allow_empty
          })
        end

      value ->
        error(:invalid_agent_string_list, base ++ [key], %{actual: type_of(value)})
    end
  end

  defp require_string(map, key, base) do
    case map[key] do
      value when is_binary(value) and byte_size(value) > 0 -> :ok
      value -> error(:agent_required_string_missing_or_invalid, base ++ [key], %{actual: value})
    end
  end

  defp require_boolean(map, key, base) do
    case map[key] do
      value when is_boolean(value) -> :ok
      value -> error(:agent_required_boolean_missing_or_invalid, base ++ [key], %{actual: value})
    end
  end

  defp error(code, path, details), do: {:error, Error.new(code, path, details)}

  defp type_of(value) when is_map(value), do: :map
  defp type_of(value) when is_list(value), do: :list
  defp type_of(value) when is_binary(value), do: :string
  defp type_of(value) when is_integer(value), do: :integer
  defp type_of(value) when is_float(value), do: :float
  defp type_of(value) when is_boolean(value), do: :boolean
  defp type_of(nil), do: nil
  defp type_of(_value), do: :other
end
