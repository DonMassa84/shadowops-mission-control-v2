defmodule ShadowOpsCore.LearningFocus do
  @moduledoc "Allowlisted, configuration-only source for the i7 learning display."

  alias ShadowOpsCore.StrategySlides

  @default Path.expand("../../../../config/learning_focus.yaml", __DIR__)
  @fallback Path.expand("../../../../config/i7_system_fallback.yaml", __DIR__)
  @contexts ~w(general career ihk technical social recovery)
  @colors %{
    "background" => "#071019",
    "panel" => "#0d1824",
    "focus" => "#4ea1ff",
    "action" => "#f6c85f",
    "success" => "#53d769",
    "error" => "#ff5c5c",
    "review" => "#a78bfa",
    "recovery" => "#4fd1c5",
    "text" => "#e8f0f7",
    "muted" => "#8ca0b3"
  }

  def load(path \\ Application.get_env(:shadowops_core, :learning_focus_path, @default)) do
    with :ok <- allowed?(path) do
      case File.stat(path) do
        {:ok, %{type: :regular}} -> read_plan(path, "LEARNING_FOCUS")
        {:error, :enoent} -> read_fallback()
        _ -> {:ok, unavailable("Learning plan not readable")}
      end
    else
      {:error, reason} -> {:ok, unavailable(reason)}
    end
  rescue
    error -> {:ok, unavailable(Exception.message(error))}
  end

  defp read_fallback do
    case File.stat(@fallback) do
      {:ok, %{type: :regular}} -> read_plan(@fallback, "SYSTEM_FALLBACK")
      _ -> {:ok, unavailable("Learning plan and system fallback not found")}
    end
  end

  defp read_plan(path, source) do
    with data when is_map(data) <- YamlElixir.read_from_file!(path),
         :ok <- valid_plan?(data) do
      {:ok, strategy} = StrategySlides.load()

      {:ok,
       data
       |> Map.put("active_context", valid_context(data["active_context"]))
       |> Map.put("allowed_contexts", @contexts)
       |> Map.put("strategy", strategy)
       |> Map.put("system_slide_count", 6)
       |> Map.put("total_available_screens", 6 + strategy["total"])
       |> Map.put("source", source)
       |> Map.put("colors", Map.merge(@colors, valid_colors(data["colors"] || %{})))
       |> Map.put("availability", "AVAILABLE")}
    else
      _ -> {:ok, unavailable("Invalid learning plan schema")}
    end
  rescue
    error -> {:ok, unavailable(Exception.message(error))}
  end

  defp allowed?(path) do
    root = Path.expand("../../../../config", __DIR__)
    expanded = Path.expand(path)

    with true <- String.starts_with?(expanded, root <> "/"),
         relative <- Path.relative_to(expanded, root),
         safe when safe != :unsafe <-
           :filelib.safe_relative_path(String.to_charlist(relative), String.to_charlist(root)) do
      :ok
    else
      _ -> {:error, "path outside allowlist"}
    end
  end

  defp valid_plan?(data) do
    with %{"title" => title, "smart" => smart} when is_binary(title) and is_binary(smart) <-
           data["goal"],
         %{"title" => current, "instruction" => instruction, "done_when" => done_when}
         when is_binary(current) and is_binary(instruction) and is_binary(done_when) <-
           data["current"],
         next when is_list(next) <- data["next"],
         true <- Enum.all?(next, &is_binary/1),
         framework when is_list(framework) <- data["writing_framework"],
         true <- Enum.all?(framework, &is_binary/1),
         kpis when is_list(kpis) <- data["kpis"],
         true <- Enum.all?(kpis, &valid_kpi?/1),
         %{
           "focus_minutes" => focus,
           "break_minutes" => break_minutes,
           "rule" => rule,
           "error_rule" => error_rule,
           "output_rule" => output_rule
         }
         when is_integer(focus) and focus > 0 and is_integer(break_minutes) and break_minutes > 0 and
                is_binary(rule) and is_binary(error_rule) and is_binary(output_rule) <-
           data["execution"] do
      :ok
    else
      _ -> {:error, "Invalid learning plan schema"}
    end
  end

  defp valid_kpi?(%{"name" => name, "target" => target}),
    do: is_binary(name) and is_binary(target)

  defp valid_kpi?(_), do: false

  defp valid_context(context) when context in @contexts, do: context
  defp valid_context(_), do: "general"

  defp valid_colors(colors),
    do:
      colors
      |> Map.take(Map.keys(@colors))
      |> Map.filter(fn {_key, value} ->
        is_binary(value) and Regex.match?(~r/^#[0-9a-fA-F]{6}$/, value)
      end)

  defp unavailable(detail),
    do: %{
      "availability" => "UNAVAILABLE",
      "detail" => detail,
      "strategy" => StrategySlides.unavailable("Learning plan unavailable"),
      "colors" => @colors
    }
end
