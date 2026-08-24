defmodule ShadowOpsWeb.FacebookLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents

  alias ShadowOps.Social.{FacebookAnalytics, FacebookCommunicationBalance, FacebookRuntime}
  alias ShadowOpsCore.{Audit, CapabilityRegistry}

  @refresh_ms 15_000

  @impl true
  def mount(_params, _session, socket) do
    analytics = read_analytics()
    runtime = read_runtime()
    balance = read_balance()

    Audit.record(:requested, "shadowops_web", "facebook_page_view", :success, %{
      privacy: "aggregate_only",
      runtime_status: runtime.status,
      balance_status: balance.status
    })

    if connected?(socket), do: Process.send_after(self(), :check_source, @refresh_ms)

    {:ok,
     socket
     |> assign(analytics: analytics)
     |> assign(runtime: runtime)
     |> assign(balance: balance)
     |> assign(capability_available?: capability_available?())
     |> assign(calculator_input: "")
     |> assign(calculator: [])}
  end

  @impl true
  def handle_info(:check_source, socket) do
    analytics = socket.assigns.analytics
    runtime = socket.assigns.runtime
    balance = socket.assigns.balance

    updated_analytics =
      if FacebookAnalytics.changed?(analytics.source.path, analytics.source.mtime),
        do: read_analytics(),
        else: analytics

    updated_runtime =
      if FacebookRuntime.changed?(runtime.source.path, runtime.source.mtime),
        do: read_runtime(),
        else: runtime

    updated_balance =
      if FacebookCommunicationBalance.changed?(balance.source.path, balance.source.mtime),
        do: read_balance(),
        else: balance

    Process.send_after(self(), :check_source, @refresh_ms)

    {:noreply,
     socket
     |> assign(analytics: updated_analytics)
     |> assign(runtime: updated_runtime)
     |> assign(balance: updated_balance)}
  end

  @impl true
  def handle_event("calculate", %{"interaction_count" => input}, socket) do
    calculator =
      calculate(input, socket.assigns.analytics.formulas, socket.assigns.analytics.thresholds)

    {:noreply, assign(socket, calculator_input: input, calculator: calculator)}
  end

  defp read_analytics do
    {:ok, analytics} = FacebookAnalytics.load()
    analytics
  end

  defp read_runtime do
    {:ok, runtime} = FacebookRuntime.load()
    runtime
  end

  defp read_balance do
    {:ok, balance} = FacebookCommunicationBalance.load()
    balance
  end

  defp capability_available?, do: match?({:ok, _}, CapabilityRegistry.lookup("facebook_analysis"))

  defp availability(%{ready?: true}, _analytics), do: "READY"
  defp availability(_runtime, %{available?: true}), do: "DEGRADED"
  defp availability(_runtime, _analytics), do: "UNAVAILABLE"

  defp effective_metrics(%{ready?: true, metrics: metrics}, _analytics), do: metrics
  defp effective_metrics(_runtime, analytics), do: analytics.metrics

  defp calculate(input, formulas, thresholds) do
    with {count, ""} <- Integer.parse(input), true <- count >= 0 do
      scores =
        Enum.map(formulas, fn formula -> {formula.name, apply_formula(formula.name, count)} end)

      classification = classify(count, thresholds)
      scores ++ if(classification, do: [{"classification", classification}], else: [])
    else
      _ -> []
    end
  end

  defp apply_formula("power_score", count), do: count / 1000
  defp apply_formula("risk_score", count), do: count / 1000 * 2
  defp apply_formula(_, _), do: nil

  defp classify(count, thresholds) do
    thresholds
    |> Enum.filter(&String.starts_with?(&1.condition || "", "interactions"))
    |> Enum.find_value(fn threshold ->
      case Regex.run(~r/>\s*(\d+)/, threshold.condition || "") do
        [_, numeric] ->
          if(count > String.to_integer(numeric), do: threshold.classification)

        _ ->
          if(threshold.condition == "else", do: threshold.classification)
      end
    end)
  end

  defp display(nil), do: "N/A"
  defp display(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 3)
  defp display(value), do: to_string(value)
  defp percent(nil), do: "N/A"
  defp percent(value), do: "#{:erlang.float_to_binary(value * 100, decimals: 1)}%"
  defp balance_chats(chats), do: Enum.take(chats, 100)
  defp mtime(nil), do: "N/A"

  defp mtime({{y, mo, d}, {h, mi, s}}),
    do: "#{y}-#{pad(mo)}-#{pad(d)} #{pad(h)}:#{pad(mi)}:#{pad(s)}"

  defp mtime(value), do: display(value)
  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")

  defp age(nil), do: "N/A"

  defp age(timestamp) do
    seconds =
      :calendar.datetime_to_gregorian_seconds(:calendar.local_time()) -
        :calendar.datetime_to_gregorian_seconds(timestamp)

    "#{max(seconds, 0)}s"
  end

  defp safe_source(path) when is_binary(path), do: Path.basename(path)
  defp safe_source(_), do: "Not available"

  attr(:label, :string, required: true)
  attr(:value, :string, required: true)

  defp status(assigns) do
    ~H"""
    <div style="border:1px solid #303641;border-radius:8px;padding:10px;background:#111419">
      <small style="display:block;color:#89919d">{@label}</small>
      <strong style="font-size:13px">{@value}</strong>
    </div>
    """
  end
end
