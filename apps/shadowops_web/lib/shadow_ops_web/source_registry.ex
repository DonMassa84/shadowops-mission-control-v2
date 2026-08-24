defmodule ShadowOpsWeb.SourceRegistry do
  @moduledoc """
  Privacy-safe automatic source registry for Mission Control V2.

  The registry never returns secret values. It only reports whether named secret bindings are
  configured and projects bounded import evidence from local JSON manifests. External connector
  processes may refresh those manifests without coupling the dashboard to provider-specific APIs.
  Missing, invalid or stale sources remain explicit and fail visible.
  """

  @sources [
    %{
      id: "gmail",
      name: "Gmail",
      domains: ~w(career administration),
      secrets: ~w(GMAIL_CLIENT_ID GMAIL_CLIENT_SECRET GMAIL_REFRESH_TOKEN)
    },
    %{
      id: "calendar",
      name: "Google Calendar",
      domains: ~w(career ihk administration health),
      secrets: ~w(GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GOOGLE_REFRESH_TOKEN)
    },
    %{
      id: "drive",
      name: "Google Drive",
      domains: ~w(ihk legal finance housing knowledge),
      secrets: ~w(GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GOOGLE_REFRESH_TOKEN)
    },
    %{
      id: "github",
      name: "GitHub",
      domains: ~w(shadowops ihk infrastructure),
      secrets: ~w(GITHUB_TOKEN)
    },
    %{id: "whatsapp", name: "WhatsApp", domains: ~w(social community), secrets: []},
    %{
      id: "telegram",
      name: "Telegram",
      domains: ~w(social community),
      secrets: ~w(TELEGRAM_BOT_TOKEN)
    },
    %{id: "obsidian", name: "Obsidian", domains: ~w(knowledge ihk), secrets: []},
    %{id: "finance", name: "Finance", domains: ~w(finance), secrets: []},
    %{id: "i7", name: "i7 Node", domains: ~w(infrastructure), secrets: []}
  ]

  @positive ~w(READY ONLINE CONNECTED AVAILABLE)

  def all, do: Enum.map(@sources, &snapshot/1)

  def snapshot(id) when is_binary(id) do
    case Enum.find(@sources, &(&1.id == id)) do
      nil -> unavailable(id, id, "UNKNOWN_SOURCE", "Unknown source")
      source -> snapshot(source)
    end
  end

  def configured_secret_names do
    @sources
    |> Enum.flat_map(& &1.secrets)
    |> Enum.uniq()
    |> Enum.filter(&secret_configured?/1)
  end

  defp snapshot(source) do
    path = import_path(source.id)
    secret_state = secret_state(source.secrets)

    case File.read(path) do
      {:ok, body} ->
        decode(source, path, body, secret_state)

      {:error, :enoent} ->
        unavailable_source(
          source,
          path,
          secret_state,
          "IMPORT_MISSING",
          "No import evidence is available"
        )

      {:error, reason} ->
        unavailable_source(source, path, secret_state, "IMPORT_UNREADABLE", inspect(reason))
    end
  end

  defp decode(source, path, body, secret_state) do
    case Jason.decode(body) do
      {:ok, data} when is_map(data) ->
        status = normalize(Map.get(data, "status", "READY"))

        %{
          id: source.id,
          name: source.name,
          kind: "external_source",
          scope: "import",
          status: status,
          health:
            normalize(
              Map.get(data, "health", if(status in @positive, do: "HEALTHY", else: "DEGRADED"))
            ),
          domains: source.domains,
          source: path,
          source_type: "LOCAL_IMPORT_EVIDENCE",
          adapter: Map.get(data, "adapter", "external_connector"),
          last_sync: Map.get(data, "last_sync", file_mtime(path)),
          record_count: non_negative_integer(Map.get(data, "record_count")),
          real_data: Map.get(data, "real_data", true) == true,
          synthetic: Map.get(data, "synthetic", false) == true,
          reachable: Map.get(data, "reachable", status in @positive) == true,
          secret_binding: secret_state,
          error_code: Map.get(data, "error_code"),
          error_message: Map.get(data, "error_message")
        }

      {:ok, _} ->
        unavailable_source(
          source,
          path,
          secret_state,
          "INVALID_SCHEMA",
          "Import evidence root must be a JSON object"
        )

      {:error, reason} ->
        unavailable_source(source, path, secret_state, "INVALID_JSON", Exception.message(reason))
    end
  end

  defp unavailable_source(source, path, secret_state, code, message) do
    %{
      id: source.id,
      name: source.name,
      kind: "external_source",
      scope: "import",
      status: "NOT_CONFIGURED",
      health: "UNAVAILABLE",
      domains: source.domains,
      source: path,
      source_type: "LOCAL_IMPORT_EVIDENCE",
      adapter: nil,
      last_sync: nil,
      record_count: nil,
      real_data: false,
      synthetic: false,
      reachable: false,
      secret_binding: secret_state,
      error_code: code,
      error_message: message
    }
  end

  defp unavailable(id, name, code, message) do
    %{
      id: id,
      name: name,
      kind: "external_source",
      scope: "import",
      status: "UNAVAILABLE",
      health: "UNAVAILABLE",
      domains: [],
      source: nil,
      source_type: "LOCAL_IMPORT_EVIDENCE",
      adapter: nil,
      last_sync: nil,
      record_count: nil,
      real_data: false,
      synthetic: false,
      reachable: false,
      secret_binding: %{required: [], configured: [], state: "NOT_REQUIRED"},
      error_code: code,
      error_message: message
    }
  end

  defp secret_state([]), do: %{required: [], configured: [], state: "NOT_REQUIRED"}

  defp secret_state(required) do
    configured = Enum.filter(required, &secret_configured?/1)

    %{
      required: required,
      configured: configured,
      state: if(length(configured) == length(required), do: "CONFIGURED", else: "MISSING")
    }
  end

  defp secret_configured?(name) do
    case System.get_env(name) do
      value when is_binary(value) -> String.trim(value) != ""
      _ -> false
    end
  end

  defp import_path(id) do
    root =
      System.get_env("SHADOWOPS_IMPORT_DIR") ||
        Path.join([System.user_home!(), ".local", "share", "shadowops", "imports"])

    Path.join(root, id <> ".json")
  end

  defp normalize(nil), do: "UNKNOWN"
  defp normalize(value), do: value |> to_string() |> String.upcase()

  defp non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_), do: nil

  defp file_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> DateTime.from_unix!(stat.mtime) |> DateTime.to_iso8601()
      _ -> nil
    end
  end
end
