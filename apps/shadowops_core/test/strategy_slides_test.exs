defmodule ShadowOpsCore.StrategySlidesTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.{LearningFocus, StrategySlides}

  @expected_counts %{
    "CORE" => 12,
    "SELF_CONTROL" => 18,
    "SOCIAL_STRATEGY" => 18,
    "CAREER_IHK" => 16,
    "TECHNICAL" => 6,
    "REVIEW" => 2
  }
  @categories Map.keys(@expected_counts)
  @contexts ~w(general career ihk technical social recovery)

  test "canonical YAML has exactly 72 unique, contract-valid slides and category counts" do
    assert {:ok,
            %{
              "availability" => "AVAILABLE",
              "validation" => "VALID_CANONICAL_72",
              "total" => 72,
              "category_counts" => @expected_counts,
              "errors" => [],
              "slides" => slides
            }} = StrategySlides.load()

    assert length(Enum.uniq_by(slides, & &1["id"])) == 72
    assert Enum.all?(slides, &(&1["category"] in @categories))
    assert Enum.all?(slides, fn slide -> Enum.all?(slide["contexts"], &(&1 in @contexts)) end)
    assert Enum.all?(slides, &(length(String.split(&1["message"], "\n")) in 1..2))
    assert Enum.map(slides, & &1["id"]) == expected_ids()
  end

  test "missing or malformed strategy YAML is unavailable without taking down system slides" do
    missing = temp_path("missing")
    malformed = temp_path("malformed")
    File.write!(malformed, "slides: [")
    on_exit(fn -> File.rm(malformed) end)

    assert {:ok, %{"availability" => "UNAVAILABLE", "slides" => []}} =
             StrategySlides.load(missing)

    assert {:ok, %{"availability" => "UNAVAILABLE", "slides" => []}} =
             StrategySlides.load(malformed)

    previous = Application.get_env(:shadowops_core, :strategy_slides_path)
    Application.put_env(:shadowops_core, :strategy_slides_path, missing)

    on_exit(fn -> restore_env(:strategy_slides_path, previous) end)

    assert {:ok,
            %{
              "availability" => "AVAILABLE",
              "strategy" => %{"availability" => "UNAVAILABLE", "slides" => []},
              "goal" => %{"title" => "KEEP YOUR MISSION"}
            }} = LearningFocus.load()
  end

  test "malformed individual records are skipped and reported" do
    {:ok, %{"slides" => [valid | _]}} = StrategySlides.load()

    {slides, errors} =
      StrategySlides.validate_records([
        valid,
        Map.put(valid, "weight", 0),
        Map.put(valid, "id", "duplicate replacement")
      ])

    assert slides == [valid]
    assert length(errors) == 2
    assert Enum.all?(errors, &is_binary(&1["reason"]))
  end

  test "missing primary learning YAML uses the verified system fallback" do
    assert {:ok,
            %{
              "availability" => "AVAILABLE",
              "source" => "SYSTEM_FALLBACK",
              "goal" => %{"title" => "KEEP YOUR MISSION"},
              "current" => %{"title" => "SELECTION > SEDUCTION"}
            }} = LearningFocus.load(temp_path("missing-learning"))
  end

  defp expected_ids do
    for(
      prefix_count <- [
        {"core", 12},
        {"self", 18},
        {"social", 18},
        {"career", 5},
        {"ihk", 11},
        {"tech", 6},
        {"review", 2}
      ],
      number <- 1..elem(prefix_count, 1),
      do: "#{elem(prefix_count, 0)}-#{String.pad_leading(Integer.to_string(number), 2, "0")}"
    )
  end

  defp temp_path(label) do
    Path.join(config_root(), ".strategy-#{label}-#{System.unique_integer([:positive])}.yaml")
  end

  defp config_root, do: Path.expand("../../../config", __DIR__)

  defp restore_env(key, nil), do: Application.delete_env(:shadowops_core, key)
  defp restore_env(key, value), do: Application.put_env(:shadowops_core, key, value)
end
