defmodule ShadowOpsCore.Resource do
  @moduledoc "Canonical, evidence-backed operational resource contract."

  @kinds ~w(node service workflow agent connector model dataset evidence approval policy run incident email_thread document)
  @risks ~w(L0 L1 L2 L3)
  @privacy ~w(local_only metadata_only aggregate_only sanitized public)
  @positive_states ~w(READY ONLINE ACTIVE HEALTHY PASS)

  @derive Jason.Encoder
  @enforce_keys [:id, :kind, :name, :source, :state, :health, :risk, :synthetic, :privacy]
  defstruct [
    :id,
    :kind,
    :name,
    :source,
    :state,
    :health,
    :risk,
    :synthetic,
    :privacy,
    :provenance,
    :last_verified_at,
    :evidence_ref,
    metadata: %{}
  ]

  def kinds, do: @kinds

  def new(attrs) when is_map(attrs) do
    resource = %__MODULE__{
      id: value(attrs, :id),
      kind: value(attrs, :kind),
      name: value(attrs, :name),
      source: value(attrs, :source),
      state: upper(value(attrs, :state)),
      health: upper(value(attrs, :health)),
      risk: upper(value(attrs, :risk)),
      synthetic: value(attrs, :synthetic),
      privacy: value(attrs, :privacy),
      provenance: value(attrs, :provenance),
      last_verified_at: value(attrs, :last_verified_at),
      evidence_ref: value(attrs, :evidence_ref),
      metadata: value(attrs, :metadata) || %{}
    }

    case validate(resource) do
      :ok -> {:ok, resource}
      {:error, _} = error -> error
    end
  end

  def new(_), do: {:error, :resource_must_be_a_map}

  def validate(%__MODULE__{} = resource) do
    with :ok <- string(resource.id, :id),
         :ok <- member(resource.kind, @kinds, :kind),
         :ok <- string(resource.name, :name),
         :ok <- string(resource.source, :source),
         :ok <- string(resource.state, :state),
         :ok <- string(resource.health, :health),
         :ok <- member(resource.risk, @risks, :risk),
         :ok <- boolean(resource.synthetic, :synthetic),
         :ok <- member(resource.privacy, @privacy, :privacy),
         :ok <- map(resource.metadata, :metadata),
         :ok <- positive_state_evidence(resource) do
      :ok
    end
  end

  defp positive_state_evidence(%{state: state, health: health} = resource) do
    if state in @positive_states or health in @positive_states do
      with false <- resource.synthetic,
           :ok <- string(resource.provenance, :provenance),
           :ok <- string(resource.evidence_ref, :evidence_ref),
           :ok <- timestamp(resource.last_verified_at) do
        :ok
      else
        true -> {:error, {:positive_state_requires_real_evidence, :synthetic}}
        {:error, _} = error -> error
      end
    else
      :ok
    end
  end

  defp string(value, _field) when is_binary(value) and value != "", do: :ok
  defp string(_value, field), do: {:error, {:invalid_field, field}}
  defp boolean(value, _field) when is_boolean(value), do: :ok
  defp boolean(_value, field), do: {:error, {:invalid_field, field}}
  defp map(value, _field) when is_map(value), do: :ok
  defp map(_value, field), do: {:error, {:invalid_field, field}}

  defp member(value, allowed, field) do
    if value in allowed, do: :ok, else: {:error, {:invalid_field, field}}
  end

  defp timestamp(%DateTime{}), do: :ok

  defp timestamp(value) when is_binary(value) do
    if match?({:ok, _, _}, DateTime.from_iso8601(value)),
      do: :ok,
      else: {:error, {:invalid_field, :last_verified_at}}
  end

  defp timestamp(_), do: {:error, {:invalid_field, :last_verified_at}}

  defp value(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> Map.get(attrs, Atom.to_string(key))
    end
  end

  defp upper(nil), do: nil
  defp upper(value), do: value |> to_string() |> String.upcase()
end
