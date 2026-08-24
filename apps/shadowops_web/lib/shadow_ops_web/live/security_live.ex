defmodule ShadowOpsWeb.SecurityLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents

  def mount(_params, _session, socket),
    do: {:ok, assign(socket, data: ShadowOpsWeb.SecurityStatus.check())}

  def render(assigns) do
    ~H"""
    <.app_shell title="Security" subtitle="Operational control verification" active="/security" availability={@data.overall} updated_at={@data.updated_at}>
      <section class="mc-grid"><.metric_card label="Security gate" value={@data.overall} status={@data.overall} source={@data.source} /><.metric_card label="Audit chain" value={@data.checks.audit_chain.status} status={@data.checks.audit_chain.status} source="audit verify" /><.metric_card label="Write authorization" value={if(@data.checks.write_authorization.enabled, do: "ENABLED", else: "DISABLED FAIL-CLOSED")} status={@data.checks.write_authorization.status} source="endpoint configuration" /><.metric_card label="Dependency advisories" value={@data.checks.dependency_advisories.status} status={@data.checks.dependency_advisories.status} source="security evidence" /></section>
      <.panel title="Control checks" description="No token or secret values are rendered."><div class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Control</th><th>Status</th><th>Evidence</th></tr></thead><tbody><tr :for={{name, check} <- Enum.sort(@data.checks)}><td>{name |> Atom.to_string() |> String.replace("_", " ")}</td><td><.status_badge status={check.status} /></td><td>{check.detail}</td></tr></tbody></table></div></.panel>
      <.panel title="Residual risks"><p class="mc-empty">No accepted residual-risk artifact is currently registered. Dependency findings must be represented by verified audit evidence before the gate can pass.</p></.panel>
    </.app_shell>
    """
  end
end
