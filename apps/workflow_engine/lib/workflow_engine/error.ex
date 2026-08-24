defmodule WorkflowEngine.Registry.Error do
  @moduledoc "Typed validation/load error returned by the schema-v2 registry loader."

  defexception [:code, :path, :details, :message]

  @type t :: %__MODULE__{
          code: atom(),
          path: [String.t()],
          details: term(),
          message: String.t()
        }

  @spec new(atom(), [String.t()], term()) :: t()
  def new(code, path \\ [], details \\ nil) do
    %__MODULE__{
      code: code,
      path: path,
      details: details,
      message: build_message(code, path, details)
    }
  end

  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = error), do: Exception.message(error)

  defp build_message(code, path, details) do
    location =
      case path do
        [] -> "registry"
        parts -> Enum.join(parts, ".")
      end

    suffix = if is_nil(details), do: "", else: ": #{inspect(details)}"
    "#{code} at #{location}#{suffix}"
  end
end
