defmodule ShadowOpsCore.StrategySlides do
  @moduledoc "Validated, configuration-only source for the i7 strategy slide pool."

  @default Path.expand("../../../../config/strategy_slides.yaml", __DIR__)
  @categories ~w(CORE SELF_CONTROL SOCIAL_STRATEGY CAREER_IHK TECHNICAL REVIEW)
  @contexts ~w(general career ihk technical social recovery)
  @priorities ~w(P0 P1 P2)
  @expected_counts %{
    "CORE" => 12,
    "SELF_CONTROL" => 18,
    "SOCIAL_STRATEGY" => 18,
    "CAREER_IHK" => 16,
    "TECHNICAL" => 6,
    "REVIEW" => 2
  }
  @category_weights %{
    "CORE" => 40,
    "SELF_CONTROL" => 15,
    "SOCIAL_STRATEGY" => 10,
    "CAREER_IHK" => 15,
    "TECHNICAL" => 15,
    "REVIEW" => 5
  }

  def load(path \\ Application.get_env(:shadowops_core, :strategy_slides_path, @default)) do
    with :ok <- allowed?(path),
         {:ok, %{type: :regular}} <- File.stat(path),
         data when is_map(data) <- YamlElixir.read_from_file!(path),
         slides when is_list(slides) <- data["slides"] do
      {valid, errors} = validate_records(slides)

      {:ok,
       %{
         "availability" => if(valid == [], do: "UNAVAILABLE", else: "AVAILABLE"),
         "validation" => validation_status(valid, errors),
         "slides" => valid,
         "errors" => errors,
         "category_counts" => category_counts(valid),
         "category_weights" => @category_weights,
         "total" => length(valid),
         "source" => "STRATEGY_SLIDES_YAML"
       }}
    else
      {:error, :enoent} -> {:ok, unavailable("Strategy slide file not found")}
      {:error, reason} when is_binary(reason) -> {:ok, unavailable(reason)}
      _ -> {:ok, unavailable("Invalid strategy slide document")}
    end
  rescue
    error -> {:ok, unavailable(Exception.message(error))}
  end

  def unavailable(detail) do
    %{
      "availability" => "UNAVAILABLE",
      "validation" => "UNAVAILABLE",
      "slides" => [],
      "errors" => [%{"reason" => detail}],
      "category_counts" => %{},
      "category_weights" => @category_weights,
      "total" => 0,
      "source" => "STRATEGY_SLIDES_YAML"
    }
  end

  def validate_records(slides) when is_list(slides) do
    slides
    |> Enum.with_index(1)
    |> Enum.reduce({[], [], MapSet.new()}, fn {slide, index}, {valid, errors, ids} ->
      case validate_slide(slide, ids) do
        {:ok, normalized} -> {[normalized | valid], errors, MapSet.put(ids, normalized["id"])}
        {:error, reason} -> {valid, [%{"index" => index, "reason" => reason} | errors], ids}
      end
    end)
    |> then(fn {valid, errors, _ids} -> {Enum.reverse(valid), Enum.reverse(errors)} end)
  end

  def validate_records(_), do: {[], [%{"reason" => "slides must be a list"}]}

  def category_counts(slides), do: Enum.frequencies_by(slides, & &1["category"])

  def canonical_deck?(slides),
    do: length(slides) == 72 and category_counts(slides) == @expected_counts

  defp validate_slide(slide, ids) when is_map(slide) do
    with {:ok, id} <- required_id(slide["id"], ids),
         {:ok, title} <- required_string(slide["title"], "title"),
         {:ok, message} <- required_message(slide["message"]),
         category when category in @categories <- slide["category"],
         weight when is_integer(weight) and weight > 0 <- slide["weight"],
         {:ok, contexts} <- required_contexts(slide["contexts"]),
         cooldown when is_integer(cooldown) and cooldown >= 0 <- slide["cooldown_minutes"],
         priority when priority in @priorities <- slide["priority"] do
      {:ok,
       %{
         "id" => id,
         "title" => title,
         "message" => message,
         "category" => category,
         "weight" => weight,
         "contexts" => contexts,
         "cooldown_minutes" => cooldown,
         "priority" => priority
       }}
    else
      nil -> {:error, "missing required field"}
      _ -> {:error, "invalid slide contract"}
    end
  end

  defp validate_slide(_, _), do: {:error, "slide must be a map"}

  defp required_id(value, ids) do
    with {:ok, id} <- required_string(value, "id"),
         true <- Regex.match?(~r/^[a-z0-9][a-z0-9-]*$/, id),
         false <- MapSet.member?(ids, id) do
      {:ok, id}
    else
      true -> {:error, "duplicate id"}
      _ -> {:error, "invalid id"}
    end
  end

  defp required_string(value, _field) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, "empty string"}
      trimmed -> {:ok, trimmed}
    end
  end

  defp required_string(_, field), do: {:error, "#{field} must be a non-empty string"}

  defp required_message(value) do
    with {:ok, message} <- required_string(value, "message"),
         lines <- String.split(message, ~r/\R/, trim: true),
         true <- length(lines) in 1..2 do
      {:ok, Enum.join(lines, "\n")}
    else
      _ -> {:error, "message must contain one or two non-empty lines"}
    end
  end

  defp required_contexts(contexts) when is_list(contexts) and contexts != [] do
    if Enum.all?(contexts, &(&1 in @contexts)),
      do: {:ok, Enum.uniq(contexts)},
      else: {:error, "invalid context"}
  end

  defp required_contexts(_), do: {:error, "contexts must be a non-empty list"}

  defp validation_status(valid, errors) do
    cond do
      valid == [] -> "UNAVAILABLE"
      errors != [] -> "PARTIAL"
      canonical_deck?(valid) -> "VALID_CANONICAL_72"
      true -> "VALID_NON_CANONICAL_COUNT"
    end
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
end
