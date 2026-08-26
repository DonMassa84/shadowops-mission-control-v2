import {Socket} from "/vendor/phoenix/phoenix.mjs"
import {LiveSocket} from "/vendor/live-view/phoenix_live_view.esm.js"

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}})
liveSocket.connect()
window.liveSocket = liveSocket

const WEBMCP_MAX_OUTPUT = 1400
const WEBMCP_SENSITIVE_KEY = /(secret|token|password|passwd|cookie|authorization|credential|private[_-]?key|session)/i

const emptyInputSchema = {
  type: "object",
  properties: {},
  additionalProperties: false
}

function detailInputSchema(param, description) {
  return {
    type: "object",
    properties: {
      [param]: {type: "string", minLength: 1, description}
    },
    required: [param],
    additionalProperties: false
  }
}

const webMcpTools = [
  {name: "shadowops_health", description: "Read ShadowOps health and registry status.", endpoint: "/api/health"},
  {name: "shadowops_readiness", description: "Read ShadowOps readiness checks.", endpoint: "/api/ready"},
  {name: "shadowops_overview", description: "Read the ShadowOps system overview.", endpoint: "/api/system/overview"},
  {name: "shadowops_layers", description: "List ShadowOps architecture layers.", endpoint: "/api/layers"},
  {name: "shadowops_layer", description: "Read one ShadowOps architecture layer by id.", endpointTemplate: "/api/layers/:id", pathParam: "id", inputSchema: detailInputSchema("id", "Layer id")},
  {name: "shadowops_projects", description: "Read the federated ShadowOps project catalog.", endpoint: "/api/projects"},
  {name: "shadowops_system", description: "Read system source-state projection.", endpoint: "/api/system"},
  {name: "shadowops_integrations", description: "Read the evidence-backed integration and source catalog.", endpoint: "/api/integrations"},
  {name: "shadowops_workflows", description: "List canonical ShadowOps workflows and execution state.", endpoint: "/api/workflows"},
  {name: "shadowops_workflow", description: "Read one canonical ShadowOps workflow by id.", endpointTemplate: "/api/workflows/:id", pathParam: "id", inputSchema: detailInputSchema("id", "Workflow id")},
  {name: "shadowops_runs", description: "List persisted ShadowOps workflow runs.", endpoint: "/api/runs"},
  {name: "shadowops_run", description: "Read one persisted ShadowOps run by id.", endpointTemplate: "/api/runs/:id", pathParam: "id", inputSchema: detailInputSchema("id", "Run id")},
  {name: "shadowops_run_evaluation", description: "Read evaluation evidence for one persisted ShadowOps run.", endpointTemplate: "/api/runs/:id/evaluation", pathParam: "id", inputSchema: detailInputSchema("id", "Run id")},
  {name: "shadowops_jobs", description: "Read the bounded persistent job queue state.", endpoint: "/api/jobs"},
  {name: "shadowops_nodes", description: "List ShadowOps compute nodes and current evidence-backed state.", endpoint: "/api/nodes"},
  {name: "shadowops_node", description: "Read one ShadowOps compute node by id.", endpointTemplate: "/api/nodes/:id", pathParam: "id", inputSchema: detailInputSchema("id", "Node id")},
  {name: "shadowops_services", description: "List ShadowOps service runtime state.", endpoint: "/api/services"},
  {name: "shadowops_service", description: "Read one ShadowOps service record by id.", endpointTemplate: "/api/services/:id", pathParam: "id", inputSchema: detailInputSchema("id", "Service id")},
  {name: "shadowops_agents", description: "Read ShadowOps agent runtime state.", endpoint: "/api/agents"},
  {name: "shadowops_ai_status", description: "Read remote-only ShadowOps AI policy and runtime status.", endpoint: "/api/ai/status"},
  {name: "shadowops_ai_models", description: "Read the governed AI model inventory projection.", endpoint: "/api/ai/models"},
  {name: "shadowops_security", description: "Read the ShadowOps security status surface.", endpoint: "/api/security/status"},
  {name: "shadowops_audit", description: "Read ShadowOps audit-chain records.", endpoint: "/api/audit"},
  {name: "shadowops_audit_verify", description: "Verify the canonical ShadowOps audit chain.", endpoint: "/api/audit/verify"},
  {name: "shadowops_audit_entry", description: "Read one ShadowOps audit entry by id.", endpointTemplate: "/api/audit/:id", pathParam: "id", inputSchema: detailInputSchema("id", "Audit entry id")},
  {name: "shadowops_logs", description: "Read recent bounded ShadowOps diagnostics.", endpoint: "/api/logs/recent"},
  {name: "shadowops_knowledge", description: "Read the ShadowOps knowledge projection.", endpoint: "/api/knowledge"},
  {name: "shadowops_evidence", description: "Read privacy-safe evidence artifact metadata.", endpoint: "/api/evidence"},
  {name: "shadowops_legal", description: "Read the ShadowOps legal-state projection.", endpoint: "/api/legal"},
  {name: "shadowops_focus", description: "Read the configured learning and focus plan.", endpoint: "/api/learning/plan"},
  {name: "shadowops_approvals", description: "List ShadowOps governance approvals without changing them.", endpoint: "/api/approvals"},
  {name: "shadowops_approval", description: "Read one ShadowOps governance approval by id without changing it.", endpointTemplate: "/api/approvals/:id", pathParam: "id", inputSchema: detailInputSchema("id", "Approval id")},
  {name: "shadowops_connectors", description: "Read external connector state without changing it.", endpoint: "/api/connectors"},
  {name: "shadowops_whatsapp", description: "Read the WhatsApp connector projection without changing it.", endpoint: "/api/connectors/whatsapp"},
  {name: "shadowops_connector", description: "Read one external connector by id without changing it.", endpointTemplate: "/api/connectors/:id", pathParam: "id", inputSchema: detailInputSchema("id", "Connector id")},
  {name: "shadowops_social", description: "Read the bounded social-source projection.", endpoint: "/api/social"},
  {name: "shadowops_facebook_balance", description: "Read the Facebook balance projection.", endpoint: "/api/social/facebook/balance"},
  {name: "shadowops_career", description: "Read the bounded career-source projection.", endpoint: "/api/career"},
  {name: "shadowops_backups", description: "Read the bounded backup-source projection.", endpoint: "/api/backups"},
  {name: "shadowops_reports", description: "Read the bounded reporting-source projection.", endpoint: "/api/reports"},
  {name: "shadowops_webmcp_check", description: "Probe all static ShadowOps WebMCP read endpoints and return only HTTP/status evidence.", kind: "check", inputSchema: emptyInputSchema}
]

function redactWebMcp(value) {
  if (Array.isArray(value)) return value.map(redactWebMcp)
  if (!value || typeof value !== "object") return value

  return Object.fromEntries(Object.entries(value).map(([key, nested]) => [
    key,
    WEBMCP_SENSITIVE_KEY.test(key) ? "[REDACTED]" : redactWebMcp(nested)
  ]))
}

function boundedWebMcpResult(endpoint, payload) {
  const body = JSON.stringify(redactWebMcp(payload))
  if (body.length <= WEBMCP_MAX_OUTPUT) return body

  return JSON.stringify({
    status: "OK_TRUNCATED",
    endpoint,
    output_truncated: true,
    preview: body.slice(0, 1000)
  })
}

function resolveWebMcpEndpoint(tool, input = {}) {
  if (tool.endpoint) return tool.endpoint
  if (!tool.endpointTemplate || !tool.pathParam) return null

  const value = input?.[tool.pathParam]
  if (typeof value !== "string" || value.trim() === "") return null

  return tool.endpointTemplate.replace(`:${tool.pathParam}`, encodeURIComponent(value.trim()))
}

async function readShadowOpsEndpoint(endpoint, signal) {
  if (!endpoint) return JSON.stringify({status: "INVALID_INPUT"})

  try {
    const response = await fetch(endpoint, {
      method: "GET",
      credentials: "same-origin",
      cache: "no-store",
      headers: {accept: "application/json"},
      signal
    })

    if (response.status === 401) {
      return JSON.stringify({status: "AUTH_REQUIRED", endpoint, http_status: 401})
    }

    if (!response.ok) {
      return JSON.stringify({status: "UNAVAILABLE", endpoint, http_status: response.status})
    }

    return boundedWebMcpResult(endpoint, await response.json())
  } catch (error) {
    const reason = error?.name === "AbortError" ? "cancelled" : "request_failed"
    return JSON.stringify({status: "UNAVAILABLE", endpoint, reason})
  }
}

async function probeShadowOpsEndpoint(endpoint, signal) {
  try {
    const response = await fetch(endpoint, {
      method: "GET",
      credentials: "same-origin",
      cache: "no-store",
      headers: {accept: "application/json"},
      signal
    })

    if (response.status === 401) return {endpoint, status: "AUTH_REQUIRED", http_status: 401}

    return {
      endpoint,
      status: response.ok ? "READY" : "UNAVAILABLE",
      http_status: response.status
    }
  } catch (error) {
    return {
      endpoint,
      status: "UNAVAILABLE",
      reason: error?.name === "AbortError" ? "cancelled" : "request_failed"
    }
  }
}

async function runShadowOpsWebMcpCheck(signal) {
  const staticTools = webMcpTools.filter(tool => tool.endpoint)
  const records = await Promise.all(staticTools.map(tool => probeShadowOpsEndpoint(tool.endpoint, signal)))
  const ready = records.filter(record => record.status === "READY").length

  return boundedWebMcpResult("/webmcp/check", {
    status: ready === records.length ? "READY" : ready > 0 ? "DEGRADED" : "UNAVAILABLE",
    ready,
    total: records.length,
    records
  })
}

async function registerShadowOpsWebMcp() {
  const modelContext = document.modelContext

  if (!modelContext || typeof modelContext.registerTool !== "function") {
    window.ShadowOpsWebMCP = {status: "UNSUPPORTED", registered: 0, expected: webMcpTools.length, readOnly: true}
    return
  }

  let registered = 0

  for (const tool of webMcpTools) {
    try {
      await modelContext.registerTool({
        name: tool.name,
        description: tool.description,
        inputSchema: tool.inputSchema || emptyInputSchema,
        annotations: {
          readOnlyHint: true,
          untrustedContentHint: true
        },
        execute: async (input = {}, context = {}) => {
          if (tool.kind === "check") return runShadowOpsWebMcpCheck(context.signal)
          return readShadowOpsEndpoint(resolveWebMcpEndpoint(tool, input), context.signal)
        }
      })
      registered += 1
    } catch (_error) {
      // WebMCP is progressive enhancement. Security/permission failures remain fail-closed.
    }
  }

  const staticCount = webMcpTools.filter(tool => tool.endpoint).length
  const detailCount = webMcpTools.filter(tool => tool.endpointTemplate).length

  window.ShadowOpsWebMCP = {
    status: registered === webMcpTools.length ? "READY" : registered > 0 ? "DEGRADED" : "BLOCKED",
    registered,
    expected: webMcpTools.length,
    staticReadTools: staticCount,
    detailReadTools: detailCount,
    readOnly: true
  }
}

function setText(node, value) {
  if (node && node.textContent !== value) node.textContent = value
}

function decorateRemoteAIPolicy() {
  document.documentElement.dataset.aiExecutionPolicy = "remote-only"

  document.querySelectorAll('a[href="/ai"]').forEach(link => {
    link.title = "AI Governance · remote-only coding · no local LLM runtime"
  })

  if (window.location.pathname !== "/") return

  const aiCard = document.querySelector('.mc-card-link[href="/ai"] .mc-metric')
  if (aiCard) {
    setText(aiCard.querySelector(".mc-metric-label>span:last-child"), "AI governance")
    setText(aiCard.querySelector(":scope>strong"), "REMOTE_ONLY")
    setText(aiCard.querySelector(":scope>p"), "Remote coding only · local LLM runtime disabled")
    setText(aiCard.querySelector(":scope>small"), "Source: REMOTE_AI_POLICY + CapabilityRegistry")
  }

  const agentsCard = document.querySelector('.mc-card-link[href="/agents"] .mc-metric')
  setText(agentsCard?.querySelector(":scope>p"), "Coding agents use explicit remote providers; no local LLM fallback")
}

registerShadowOpsWebMcp()
decorateRemoteAIPolicy()
window.addEventListener("phx:page-loading-stop", decorateRemoteAIPolicy)
