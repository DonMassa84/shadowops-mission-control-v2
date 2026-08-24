defmodule ShadowOpsWeb.I7DisplayTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.LearningFocus

  test "display and learning API render the real configured YAML" do
    assert request("/display/i7", :head).status == 200
    display = request("/display/i7")
    assert display.status == 200
    assert display.resp_body =~ "KEEP YOUR MISSION"
    assert display.resp_body =~ "SELECTION &gt; SEDUCTION"
    assert display.resp_body =~ "Autonomie statt Manipulation"
    assert display.resp_body =~ "DONE WHEN"
    assert display.resp_body =~ "MISSION FIRST"
    assert display.resp_body =~ "STRATEGY 1 / 72"
    assert length(Regex.scan(~r/data-slide="[^"]+"/, display.resp_body)) == 6

    api = request("/api/learning/plan")
    assert api.status == 200
    plan = Jason.decode!(api.resp_body)
    assert plan["availability"] == "AVAILABLE"
    assert plan["current"]["title"] == "SELECTION > SEDUCTION"
    assert plan["goal"]["smart"] =~ "keine Manipulation"
    assert length(plan["writing_framework"]) == 10
    assert plan["strategy"]["validation"] == "VALID_CANONICAL_72"
    assert plan["strategy"]["total"] == 72
    assert length(plan["strategy"]["slides"]) == 72
    assert plan["system_slide_count"] == 6
    assert plan["total_available_screens"] == 78
  end

  test "missing source is unavailable and rotation remains disabled" do
    previous = Application.get_env(:shadowops_core, :learning_focus_path)
    Application.put_env(:shadowops_core, :learning_focus_path, "/tmp/outside-learning-focus.yaml")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:shadowops_core, :learning_focus_path, previous),
        else: Application.delete_env(:shadowops_core, :learning_focus_path)
    end)

    assert {:ok, %{"availability" => "UNAVAILABLE"}} = LearningFocus.load()
    response = request("/display/i7")
    assert response.status == 200
    assert response.resp_body =~ "UNAVAILABLE"
    assert response.resp_body =~ ~s(data-available="UNAVAILABLE")
    refute response.resp_body =~ "SELECTION &gt; SEDUCTION"
  end

  test "rotation asset has required timing, refresh, controls and burn-in protection" do
    response = request("/assets/i7-display.js")
    assert response.status == 200
    assert response.resp_body =~ "SLIDE_INTERVAL_MS = 12000"
    assert response.resp_body =~ "DATA_REFRESH_MS = 60000"
    assert response.resp_body =~ "BURN_IN_INTERVAL_MS"
    assert response.resp_body =~ "STRATEGY_PER_SYSTEM = 5"
    assert response.resp_body =~ ~s(fetch("/api/learning/plan")
    assert response.resp_body =~ "ArrowRight"
    assert response.resp_body =~ "ArrowLeft"
    assert response.resp_body =~ "event.key.toLowerCase() === \"s\""
    assert response.resp_body =~ "event.key.toLowerCase() === \"c\""
    assert response.resp_body =~ "event.key.toLowerCase() === \"r\""

    selector = request("/assets/i7-rotation.js")
    assert selector.status == 200
    assert selector.resp_body =~ "BASE_CATEGORY_WEIGHTS"
    assert selector.resp_body =~ "Europe/Berlin"
    assert selector.resp_body =~ "cooldown_minutes"
    assert selector.resp_body =~ "slide.id !== currentId"
  end

  test "malformed individual strategy slide is skipped without crashing the route" do
    previous = Application.get_env(:shadowops_core, :strategy_slides_path)

    path =
      Path.join(config_root(), ".strategy-partial-#{System.unique_integer([:positive])}.yaml")

    File.write!(path, """
    slides:
      - id: test-valid
        title: Valid test fixture
        message: Test-only structural fixture
        category: CORE
        weight: 10
        contexts: [general]
        cooldown_minutes: 30
        priority: P0
      - id: test-invalid
        title: Invalid test fixture
        message: Test-only structural fixture
        category: UNKNOWN
        weight: 0
        contexts: []
        cooldown_minutes: -1
        priority: INVALID
    """)

    Application.put_env(:shadowops_core, :strategy_slides_path, path)

    on_exit(fn ->
      restore_strategy_path(previous)
      File.rm(path)
    end)

    response = request("/display/i7")
    assert response.status == 200
    assert response.resp_body =~ "Valid test fixture"

    api = request("/api/learning/plan")
    assert api.status == 200
    plan = Jason.decode!(api.resp_body)
    assert plan["strategy"]["validation"] == "PARTIAL"
    assert plan["strategy"]["total"] == 1
    assert length(plan["strategy"]["errors"]) == 1
  end

  test "missing strategy YAML preserves six system slides and display availability" do
    previous = Application.get_env(:shadowops_core, :strategy_slides_path)

    missing =
      Path.join(config_root(), ".missing-strategy-#{System.unique_integer([:positive])}.yaml")

    Application.put_env(:shadowops_core, :strategy_slides_path, missing)
    on_exit(fn -> restore_strategy_path(previous) end)

    response = request("/display/i7")
    assert response.status == 200
    assert response.resp_body =~ ~s(data-available="AVAILABLE")
    assert length(Regex.scan(~r/data-slide="[^"]+"/, response.resp_body)) == 6
    assert response.resp_body =~ "KEEP YOUR MISSION"
    refute response.resp_body =~ "MISSION FIRST"

    plan = request("/api/learning/plan").resp_body |> Jason.decode!()
    assert plan["availability"] == "AVAILABLE"
    assert plan["strategy"]["availability"] == "UNAVAILABLE"
    assert plan["strategy"]["slides"] == []
  end

  test "missing allowlisted learning YAML uses six-slide fallback without a 500" do
    previous = Application.get_env(:shadowops_core, :learning_focus_path)

    missing =
      Path.join(config_root(), ".missing-learning-#{System.unique_integer([:positive])}.yaml")

    Application.put_env(:shadowops_core, :learning_focus_path, missing)
    on_exit(fn -> restore_learning_path(previous) end)

    response = request("/display/i7")
    assert response.status == 200
    assert response.resp_body =~ "KEEP YOUR MISSION"
    assert length(Regex.scan(~r/data-slide="[^"]+"/, response.resp_body)) == 6

    plan = request("/api/learning/plan").resp_body |> Jason.decode!()
    assert plan["availability"] == "AVAILABLE"
    assert plan["source"] == "SYSTEM_FALLBACK"
  end

  test "malformed learning plan shapes render explicit unavailable state without a 500" do
    previous = Application.get_env(:shadowops_core, :learning_focus_path)

    root =
      Path.join(config_root(), ".hardening-i7-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)

    on_exit(fn ->
      restore_learning_path(previous)
      File.rm_rf(root)
    end)

    cases = [
      {"goal-string", ~s(goal: "string"\n)},
      {"current-null", "current: null\n"},
      {"next-map", "next: {}\n"},
      {"writing-framework-string", ~s(writing_framework: "text"\n)},
      {"kpis-null", "kpis: null\n"},
      {"execution-list", "execution: []\n"}
    ]

    Enum.each(cases, fn {name, yaml} ->
      path = Path.join(root, name <> ".yaml")
      File.write!(path, yaml)
      Application.put_env(:shadowops_core, :learning_focus_path, path)

      assert {:ok, %{"availability" => "UNAVAILABLE"}} = LearningFocus.load()

      response = request("/display/i7")
      assert response.status == 200
      assert response.resp_body =~ ~s(data-available="UNAVAILABLE")
      assert response.resp_body =~ "UNAVAILABLE"
    end)
  end

  test "learning plan confinement blocks traversal, prefix collisions and symlink escapes" do
    config_root = config_root()

    blocked_paths = [
      Path.join(config_root, "../outside.yaml"),
      Path.join(System.tmp_dir!(), "shadowops-absolute-outside.yaml"),
      config_root <> "-collision/learning.yaml"
    ]

    Enum.each(blocked_paths, fn path ->
      assert {:ok,
              %{
                "availability" => "UNAVAILABLE",
                "detail" => "path outside allowlist"
              }} = LearningFocus.load(path)
    end)

    suffix = System.unique_integer([:positive])
    outside = Path.join(System.tmp_dir!(), "shadowops-learning-outside-#{suffix}.yaml")
    link = Path.join(config_root, ".hardening-learning-link-#{suffix}.yaml")
    File.cp!(Path.join(config_root, "learning_focus.yaml"), outside)
    File.ln_s!(outside, link)

    on_exit(fn ->
      File.rm(link)
      File.rm(outside)
    end)

    assert {:ok,
            %{
              "availability" => "UNAVAILABLE",
              "detail" => "path outside allowlist"
            }} = LearningFocus.load(link)
  end

  defp request(path, method \\ :get) do
    method
    |> Plug.Test.conn(path)
    |> ShadowOpsWeb.Endpoint.call([])
  end

  defp restore_learning_path(nil),
    do: Application.delete_env(:shadowops_core, :learning_focus_path)

  defp restore_learning_path(path),
    do: Application.put_env(:shadowops_core, :learning_focus_path, path)

  defp restore_strategy_path(nil),
    do: Application.delete_env(:shadowops_core, :strategy_slides_path)

  defp restore_strategy_path(path),
    do: Application.put_env(:shadowops_core, :strategy_slides_path, path)

  defp config_root, do: Path.expand("../../../config", __DIR__)
end
