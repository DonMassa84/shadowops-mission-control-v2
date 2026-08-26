defmodule Mix.Tasks.Shadowops.Projects.SeedTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Shadowops.Projects.Seed

  test "invalid existing catalog fails closed without overwriting it" do
    path =
      Path.join(
        System.tmp_dir!(),
        "shadowops-project-catalog-seed-#{System.unique_integer([:positive])}.json"
      )

    previous = System.get_env("SHADOWOPS_PROJECT_CATALOG")
    File.write!(path, "{invalid")
    System.put_env("SHADOWOPS_PROJECT_CATALOG", path)

    on_exit(fn ->
      File.rm(path)

      if previous do
        System.put_env("SHADOWOPS_PROJECT_CATALOG", previous)
      else
        System.delete_env("SHADOWOPS_PROJECT_CATALOG")
      end
    end)

    Mix.Task.reenable("shadowops.projects.seed")

    assert_raise Mix.Error, ~r/PROJECT_CATALOG_SEED=BLOCKED code=INVALID_JSON/, fn ->
      Seed.run([])
    end

    assert File.read!(path) == "{invalid"
  end
end
