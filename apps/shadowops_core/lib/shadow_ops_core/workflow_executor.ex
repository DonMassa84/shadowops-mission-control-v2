defmodule ShadowOpsCore.WorkflowExecutor do
  @moduledoc "Fail-closed, no-shell executor for approved workflows from the canonical registry."
  @max_output 16_000

  @doc "Returns the immutable execution-boundary contract used by runtime security checks."
  def security_contract do
    %{
      execution_mode: "DIRECT_ARGV",
      shell_interpolation: false,
      runtime_policy: "ABSOLUTE_REGULAR_FILE",
      arguments_policy: "BINARY_LIST_ONLY",
      output_redaction: true,
      max_output_bytes: @max_output
    }
  end

  def execute(workflow, input) when is_map(workflow) and is_map(input) do
    runtime = workflow["runtime"]
    args = if Map.has_key?(workflow, "argv"), do: workflow["argv"], else: input["args"] || []

    with :ok <- runnable?(workflow),
         :ok <- safe_runtime?(runtime, workflow["status"]),
         :ok <- safe_args?(args) do
      {output, exit_code} = System.cmd(runtime, args, stderr_to_stdout: true)
      result = %{summary: sanitize(output), exit_code: exit_code}
      if exit_code == 0, do: {:ok, result}, else: {:error, result}
    else
      {:error, reason} -> {:error, %{summary: inspect(reason), exit_code: nil}}
    end
  rescue
    error -> {:error, %{summary: Exception.message(error), exit_code: nil}}
  end

  defp runnable?(%{"status" => status}) when status in ["active", "VERIFIED_EXECUTABLE"], do: :ok
  defp runnable?(_), do: {:error, :workflow_not_executable}

  defp safe_runtime?(runtime, "VERIFIED_EXECUTABLE") when is_binary(runtime) do
    expanded = Path.expand(runtime)

    if Path.type(expanded) == :absolute and expanded == runtime and File.regular?(expanded) and
         System.find_executable(runtime) == runtime,
       do: :ok,
       else: {:error, :runtime_not_available}
  end

  defp safe_runtime?(runtime, _status) when is_binary(runtime) do
    expanded = Path.expand(runtime)

    if Path.type(expanded) == :absolute and expanded == runtime and File.regular?(expanded),
      do: :ok,
      else: {:error, :runtime_not_available}
  end

  defp safe_runtime?(_, _status), do: {:error, :runtime_not_available}

  defp safe_args?(args) when is_list(args),
    do: if(Enum.all?(args, &is_binary/1), do: :ok, else: {:error, :invalid_arguments})

  defp safe_args?(_), do: {:error, :invalid_arguments}

  defp sanitize(output) do
    output
    |> String.replace(
      ~r/(?i)(token|secret|password|authorization)\s*[=:]\s*\S+/,
      "\\1=[REDACTED]"
    )
    |> String.slice(0, @max_output)
  end
end
