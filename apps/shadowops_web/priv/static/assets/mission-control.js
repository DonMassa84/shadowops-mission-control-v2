import {Socket} from "/vendor/phoenix/phoenix.mjs"
import {LiveSocket} from "/vendor/live-view/phoenix_live_view.esm.js"

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}})
liveSocket.connect()
window.liveSocket = liveSocket

const WEBMCP_MAX_OUTPUT = 1400
const WEBMCP_SENSITIVE_KEY = /(secret|token|password|passwd|cookie|authorization|credential|private[_-]?key|session)/i

const webMcpEndpoints = [
  ["shadowops_health", "Read ShadowOps health and registry status.", "/api/health"],
  ["shadowops_readiness", "Read ShadowOps readiness checks.", "/api/ready"],
  ["shadowops_overview", "Read the ShadowOps system overview.", "/api/system/overview"],
  ["shadowops_workflows", "List canonical ShadowOps workflows and execution state.", "/api/workflows"],
  ["shadowops_runs", "List persisted ShadowOps workflow runs.", "/api/runs"],
  ["shadowops_nodes", "List ShadowOps compute nodes and current evidence-backed state.", "/api/nodes"],
  ["shadowops_services", "List ShadowOps service runtime state.", "/api/services"],
  ["shadowops_approvals", "List ShadowOps governance approvals without changing them.", "/api/approvals"],
  ["shadowops_audit", "Read ShadowOps audit-chain records.", "/api/audit"],
  ["shadowops_logs", "Read recent bounded ShadowOps diagnostics.", "/api/logs/recent"],
  ["shadowops_security", "Read the ShadowOps security status surface.", "/api/security/status"]
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

async function readShadowOpsEndpoint(endpoint) {
  try {
    const response = await fetch(endpoint, {
      method: "GET",
      credentials: "same-origin",
      cache: "no-store",
      headers: {accept: "application/json"}
    })

    if (response.status === 401) {
      return JSON.stringify({status: "AUTH_REQUIRED", endpoint, http_status: 401})
    }

    if (!response.ok) {
      return JSON.stringify({status: "UNAVAILABLE", endpoint, http_status: response.status})
    }

    return boundedWebMcpResult(endpoint, await response.json())
  } catch (_error) {
    return JSON.stringify({status: "UNAVAILABLE", endpoint, reason: "request_failed"})
  }
}

async function registerShadowOpsWebMcp() {
  const modelContext = document.modelContext

  if (!modelContext || typeof modelContext.registerTool !== "function") {
    window.ShadowOpsWebMCP = {status: "UNSUPPORTED", registered: 0}
    return
  }

  let registered = 0

  for (const [name, description, endpoint] of webMcpEndpoints) {
    try {
      await modelContext.registerTool({
        name,
        description,
        inputSchema: {
          type: "object",
          properties: {},
          additionalProperties: false
        },
        annotations: {
          readOnlyHint: true,
          untrustedContentHint: true
        },
        execute: async () => readShadowOpsEndpoint(endpoint)
      })
      registered += 1
    } catch (_error) {
      // WebMCP is progressive enhancement. Security/permission failures remain fail-closed.
    }
  }

  window.ShadowOpsWebMCP = {
    status: registered === webMcpEndpoints.length ? "READY" : registered > 0 ? "DEGRADED" : "BLOCKED",
    registered,
    expected: webMcpEndpoints.length,
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
