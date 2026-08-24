defmodule AgentRuntime.AgentSpec do
  @moduledoc """
  Runtime-neutral contract for ShadowOps agents.

  The contract deliberately separates an agent's capabilities from the
  executor that implements them. This allows Elixir, Python and external TCC
  workers to be governed by the same policy surface.
  """

  @enforce_keys [:id, :version]
  defstruct id: nil,
            version: nil,
            capabilities: [],
            required_inputs: [],
            produced_outputs: [],
            permissions: [],
            timeout_ms: 30_000,
            retry_policy: %{max_attempts: 1, backoff_ms: 0},
            human_review_policy: :none,
            evidence_policy: %{required: false},
            executor: :elixir,
            metadata: %{}

  @type t :: %__MODULE__{
          id: String.t(),
          version: String.t(),
          capabilities: [String.t()],
          required_inputs: [String.t()],
          produced_outputs: [String.t()],
          permissions: [String.t()],
          timeout_ms: pos_integer(),
          retry_policy: map(),
          human_review_policy: :none | :required | :conditional,
          evidence_policy: map(),
          executor: atom() | String.t(),
          metadata: map()
        }

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    spec = struct(__MODULE__, attrs)

    case validate(spec) do
      :ok -> {:ok, spec}
      {:error, _reason} = error -> error
    end
  rescue
    KeyError -> {:error, :unknown_agent_spec_field}
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = spec) do
    with :ok <- non_empty_string(spec.id, :id),
         :ok <- non_empty_string(spec.version, :version),
         :ok <- string_list(spec.capabilities, :capabilities),
         :ok <- string_list(spec.required_inputs, :required_inputs),
         :ok <- string_list(spec.produced_outputs, :produced_outputs),
         :ok <- string_list(spec.permissions, :permissions),
         :ok <- positive_integer(spec.timeout_ms, :timeout_ms),
         :ok <- retry_policy(spec.retry_policy),
         :ok <- review_policy(spec.human_review_policy),
         :ok <- map_value(spec.evidence_policy, :evidence_policy),
         :ok <- map_value(spec.metadata, :metadata) do
      :ok
    end
  end

  defp non_empty_string(value, _field) when is_binary(value) and byte_size(value) > 0, do: :ok
  defp non_empty_string(_value, field), do: {:error, {:invalid_field, field}}

  defp string_list(value, field) when is_list(value) do
    if Enum.all?(value, &(is_binary(&1) and byte_size(&1) > 0)),
      do: :ok,
      else: {:error, {:invalid_field, field}}
  end

  defp string_list(_value, field), do: {:error, {:invalid_field, field}}

  defp positive_integer(value, _field) when is_integer(value) and value > 0, do: :ok
  defp positive_integer(_value, field), do: {:error, {:invalid_field, field}}

  defp retry_policy(%{max_attempts: attempts} = policy)
       when is_integer(attempts) and attempts >= 1 do
    backoff = Map.get(policy, :backoff_ms, 0)

    if is_integer(backoff) and backoff >= 0,
      do: :ok,
      else: {:error, {:invalid_field, :retry_policy}}
  end

  defp retry_policy(_value), do: {:error, {:invalid_field, :retry_policy}}

  defp review_policy(value) when value in [:none, :required, :conditional], do: :ok
  defp review_policy(_value), do: {:error, {:invalid_field, :human_review_policy}}

  defp map_value(value, _field) when is_map(value), do: :ok
  defp map_value(_value, field), do: {:error, {:invalid_field, field}}
end
