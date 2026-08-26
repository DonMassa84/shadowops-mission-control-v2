defmodule ShadowOpsWeb.Router do
  use Phoenix.Router

  import Phoenix.LiveDashboard.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:protect_from_forgery)
    plug(:fetch_live_flash)
    plug(ShadowOpsWeb.Plugs.WebMCPHeaders)
  end

  pipeline :runtime_dashboard do
    plug(ShadowOpsWeb.Plugs.RuntimeDashboardAccess)
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(ShadowOpsWeb.Plugs.Security, :require_read)
  end

  pipeline :control_plane_write do
    plug(:accepts, ["json"])
    plug(ShadowOpsWeb.Plugs.Security)
    plug(ShadowOpsWeb.Plugs.Security, :require_write_actor)
    plug(ShadowOpsWeb.Plugs.RateLimitPlug)
  end

  scope "/" do
    pipe_through([:browser, :runtime_dashboard])
    live_dashboard("/runtime", metrics: ShadowOpsWeb.Telemetry)
  end

  scope "/", ShadowOpsWeb do
    pipe_through(:browser)

    live("/", DashboardLive, :index)
    live("/layers", LayersLive, :index)
    live("/layers/:id", LayerDetailLive, :show)
    live("/infrastructure", InfrastructureLive, :index)
    live("/compute", ComputeLive, :index)
    live("/workflows", WorkflowsLive, :index)
    live("/workflows/:id", WorkflowDetailLive, :show)
    live("/runs", RunsLive, :index)
    live("/runs/:id", RunsLive, :show)
    live("/jobs", JobsLive, :index)
    live("/nodes", NodesLive, :index)
    live("/services", ServicesLive, :index)
    live("/agents", AgentsLive, :index)
    live("/ai", AILive, :index)
    live("/focus", FocusLive, :index)
    live("/integrations", IntegrationsLive, :index)
    live("/security", SecurityLive, :index)
    live("/approvals", ApprovalsLive, :index)
    live("/approvals/:id", ApprovalDetailLive, :show)
    live("/audit", AuditLive, :index)
    live("/logs", LogsLive, :index)
    live("/knowledge", KnowledgeLive, :index)
    live("/career", ModuleLive, :career)
    live("/backups", ModuleLive, :backups)
    live("/reporting", ModuleLive, :reporting)
    live("/evidence", EvidenceLive, :index)
    live("/legal", LegalLive, :index)
    live("/settings", SettingsLive, :index)
    live("/projects", ProjectDomainsLive, :index)
    live("/projects/federated", ProjectCatalogLive, :index)
    live("/projects/shadowops", ProjectDomainLive, :shadowops)
    live("/projects/infrastructure", ProjectDomainLive, :infrastructure)
    live("/projects/career", ProjectDomainLive, :career)
    live("/projects/finance", ProjectDomainLive, :finance)
    live("/projects/investigations", ProjectDomainLive, :investigations)
    live("/projects/legal", ProjectDomainLive, :legal)
    live("/projects/ihk", ProjectDomainLive, :ihk)
    live("/projects/community", ProjectDomainLive, :community)
    live("/projects/social", ProjectDomainLive, :social)
    live("/projects/knowledge", ProjectDomainLive, :knowledge)
    live("/projects/chatgpt", ProjectDomainLive, :chatgpt)
    live("/projects/housing", ProjectDomainLive, :housing)
    live("/projects/administration", ProjectDomainLive, :administration)
    live("/projects/health", ProjectDomainLive, :health)
    live("/projects/learning", ProjectDomainLive, :learning)
    live("/projects/personal_framework", ProjectDomainLive, :personal_framework)
    live("/social", ModuleLive, :social)
    live("/social/facebook", FacebookLive, :index)
    live("/social/review", SocialReviewLive, :index)
    live("/social/messenger", SocialUnavailableLive, :messenger)
    live("/social/whatsapp", SocialUnavailableLive, :whatsapp)
    live("/social/telegram", SocialUnavailableLive, :telegram)
    head("/display/i7", I7ProbeController, :head)
    live("/display/i7", I7DisplayLive, :index)
  end

  scope "/api", ShadowOpsWeb do
    pipe_through(:api)

    get("/health", HealthController, :show)
    get("/ready", ReadinessController, :show)
    get("/system/overview", SystemOverviewController, :show)
    get("/layers", LayersController, :index)
    get("/layers/:id", LayersController, :show)
    get("/projects", ProjectCatalogController, :index)
    get("/system", ModuleSourcesController, :system)
    get("/integrations", IntegrationsController, :index)
    get("/workflows", WorkflowsController, :index)
    get("/workflows/:id", WorkflowsController, :show)
    get("/runs", RunsController, :index)
    get("/runs/:id", RunsController, :show)
    get("/runs/:id/evaluation", RunsController, :evaluation)
    get("/jobs", JobsController, :index)
    get("/nodes", NodesController, :index)
    get("/nodes/:id", NodesController, :show)
    get("/services", ServicesController, :index)
    get("/services/:id", ServicesController, :show)
    get("/agents", AgentsController, :index)
    get("/ai", AIStatusController, :status)
    get("/ai/status", AIStatusController, :status)
    get("/ai/models", AIStatusController, :models)
    get("/security/status", SecurityController, :status)
    get("/audit", AuditController, :index)
    get("/audit/verify", AuditController, :verify)
    get("/audit/:id", AuditController, :show)
    get("/logs", LogsController, :recent)
    get("/logs/recent", LogsController, :recent)
    get("/knowledge", KnowledgeController, :index)
    get("/evidence", EvidenceController, :index)
    get("/legal", LegalController, :index)
    get("/learning/plan", LearningController, :plan)
    get("/approvals", ApprovalsController, :index)
    get("/approvals/:id", ApprovalsController, :show)
    get("/connectors", ModuleSourcesController, :connectors)
    get("/connectors/whatsapp", ModuleSourcesController, :whatsapp)
    get("/connectors/:id", ModuleSourcesController, :connector)
    get("/social", ModuleSourcesController, :social)
    get("/social/facebook/balance", FacebookBalanceController, :index)
    get("/career", ModuleSourcesController, :career)
    get("/backups", ModuleSourcesController, :backups)
    get("/reports", ModuleSourcesController, :reporting)
  end

  scope "/api", ShadowOpsWeb do
    pipe_through(:control_plane_write)
    post("/workflows/:id/run", WorkflowsController, :run)
    post("/approvals", ApprovalsController, :create)
    post("/nodes/:id/actions/healthcheck", NodesController, :healthcheck)
    post("/nodes/:id/actions/start", NodesController, :start)
    post("/nodes/:id/actions/stop", NodesController, :stop)
    post("/services/:id/actions/:action", ServicesController, :operate)
    post("/approvals/:id/approve", ApprovalsController, :approve)
    post("/approvals/:id/reject", ApprovalsController, :reject)
  end

  scope "/", ShadowOpsWeb do
    pipe_through(:api)
    get("/health", HealthController, :show)
    get("/ready", ReadinessController, :show)
    get("/metrics", MetricsController, :show)
  end
end
