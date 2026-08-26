import {Socket} from "/vendor/phoenix/phoenix.mjs"
import {LiveSocket} from "/vendor/live-view/phoenix_live_view.esm.js"

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}})
liveSocket.connect()
window.liveSocket = liveSocket

const destinations = [
  ["Mission Control", "/", "dashboard overview command center"],
  ["Layer Health", "/layers", "architecture readiness layers"],
  ["Infrastructure", "/infrastructure", "compute runtime infrastructure"],
  ["Workflows", "/workflows", "automation canonical workflows"],
  ["Runs", "/runs", "execution history lifecycle"],
  ["Services", "/services", "services integrations"],
  ["Nodes", "/nodes", "ryzen i7 compute nodes"],
  ["Backups", "/backups", "backup restore evidence"],
  ["Projects", "/projects", "project domains"],
  ["Federated Projects", "/projects/federated", "github chatgpt federation"],
  ["ChatGPT Project", "/projects/chatgpt", "chatgpt project"],
  ["Finance", "/projects/finance", "finance project"],
  ["Investigations", "/projects/investigations", "investigations project"],
  ["IHK", "/projects/ihk", "ihk project"],
  ["Community", "/projects/community", "community project"],
  ["Agents", "/agents", "agent runtime evidence"],
  ["AI Governance", "/ai", "remote only coding governed local product runtime ollama"],
  ["Knowledge", "/knowledge", "knowledge retrieval"],
  ["Career", "/career", "career applications"],
  ["Reporting", "/reporting", "reports"],
  ["Social", "/social", "social overview"],
  ["Facebook", "/social/facebook", "facebook evidence"],
  ["Social Review", "/social/review", "social review"],
  ["Messenger", "/social/messenger", "messenger"],
  ["WhatsApp", "/social/whatsapp", "whatsapp"],
  ["Telegram", "/social/telegram", "telegram"],
  ["Approvals", "/approvals", "governance approvals decisions"],
  ["Security", "/security", "security policy privacy"],
  ["Audit", "/audit", "audit hash chain"],
  ["Evidence", "/evidence", "evidence provenance"],
  ["Legal", "/legal", "legal registry"],
  ["Logs", "/logs", "diagnostics logs"],
  ["i7 Display", "/display/i7", "display kiosk"],
  ["Health", "/health", "health endpoint"],
  ["Readiness", "/ready", "readiness endpoint"]
]

function buildCommandPalette() {
  if (document.getElementById("mc-command-palette")) return

  const wrapper = document.createElement("div")
  wrapper.id = "mc-command-palette"
  wrapper.className = "mc-palette"
  wrapper.hidden = true
  wrapper.innerHTML = `
    <div class="mc-palette-backdrop" data-mc-close></div>
    <section class="mc-palette-dialog" role="dialog" aria-modal="true" aria-label="ShadowOps command palette">
      <header class="mc-palette-head">
        <div>
          <span class="mc-palette-kicker">COMMAND PALETTE</span>
          <strong>Jump to a control surface</strong>
        </div>
        <kbd>ESC</kbd>
      </header>
      <div class="mc-palette-search-wrap">
        <span aria-hidden="true">⌕</span>
        <input id="mc-palette-search" type="search" autocomplete="off" spellcheck="false" placeholder="Search nodes, approvals, workflows…" aria-label="Search ShadowOps destinations" />
        <kbd>↵</kbd>
      </div>
      <div id="mc-palette-results" class="mc-palette-results" role="listbox"></div>
      <footer class="mc-palette-foot"><span><kbd>↑</kbd><kbd>↓</kbd> select</span><span><kbd>↵</kbd> open</span><span><kbd>Ctrl</kbd><kbd>K</kbd> toggle</span></footer>
    </section>`
  document.body.appendChild(wrapper)

  const input = wrapper.querySelector("#mc-palette-search")
  const results = wrapper.querySelector("#mc-palette-results")
  let filtered = destinations
  let selected = 0

  const render = () => {
    const query = input.value.trim().toLowerCase()
    filtered = destinations.filter(([label, path, terms]) => `${label} ${path} ${terms}`.toLowerCase().includes(query))
    selected = Math.min(selected, Math.max(filtered.length - 1, 0))
    results.innerHTML = filtered.length
      ? filtered.map(([label, path], index) => `
          <a class="mc-palette-item${index === selected ? " is-selected" : ""}" href="${path}" role="option" aria-selected="${index === selected}">
            <span><strong>${label}</strong><small>${path}</small></span><span aria-hidden="true">→</span>
          </a>`).join("")
      : `<div class="mc-palette-empty">No matching ShadowOps surface.</div>`
  }

  const open = () => {
    wrapper.hidden = false
    document.documentElement.classList.add("mc-palette-open")
    input.value = ""
    selected = 0
    render()
    requestAnimationFrame(() => input.focus())
  }

  const close = () => {
    wrapper.hidden = true
    document.documentElement.classList.remove("mc-palette-open")
  }

  wrapper.addEventListener("click", event => {
    if (event.target.closest("[data-mc-close]")) close()
    const item = event.target.closest(".mc-palette-item")
    if (item) close()
  })

  input.addEventListener("input", () => {
    selected = 0
    render()
  })

  input.addEventListener("keydown", event => {
    if (event.key === "ArrowDown") {
      event.preventDefault()
      selected = Math.min(selected + 1, Math.max(filtered.length - 1, 0))
      render()
      results.querySelector(".is-selected")?.scrollIntoView({block: "nearest"})
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      selected = Math.max(selected - 1, 0)
      render()
      results.querySelector(".is-selected")?.scrollIntoView({block: "nearest"})
    } else if (event.key === "Enter" && filtered[selected]) {
      event.preventDefault()
      window.location.assign(filtered[selected][1])
    }
  })

  window.ShadowOpsCommandPalette = {open, close}
}

function installCommandTrigger() {
  const meta = document.querySelector(".mc-topbar-meta")
  if (!meta || meta.querySelector("[data-mc-command]")) return
  const button = document.createElement("button")
  button.type = "button"
  button.className = "mc-command-trigger"
  button.dataset.mcCommand = "true"
  button.setAttribute("aria-label", "Open command palette")
  button.innerHTML = `<span aria-hidden="true">⌕</span><span>Command</span><kbd>Ctrl K</kbd>`
  button.addEventListener("click", () => window.ShadowOpsCommandPalette?.open())
  meta.prepend(button)
}

function setText(node, value) {
  if (node && node.textContent !== value) node.textContent = value
}

function setBadge(badge, label, tone = "success") {
  if (!badge) return
  const expectedClass = `mc-badge is-${tone}`
  if (badge.className !== expectedClass || badge.textContent.trim() !== label) {
    badge.className = expectedClass
    badge.innerHTML = `<span aria-hidden="true"></span>${label}`
  }
}

function decorateDashboardPolicy() {
  if (window.location.pathname !== "/") return

  const aiCard = document.querySelector('.mc-card-link[href="/ai"] .mc-metric')
  if (aiCard) {
    setText(aiCard.querySelector(".mc-metric-label>span:last-child"), "AI governance")
    setText(aiCard.querySelector(":scope>strong"), "SPLIT POLICY")
    setText(aiCard.querySelector(":scope>p"), "Coding REMOTE_ONLY · governed local product runtime")
    setText(aiCard.querySelector(":scope>small"), "Source: REMOTE_AI_POLICY + CapabilityRegistry")
    setBadge(aiCard.querySelector(".mc-badge"), "GOVERNED", "success")
  }

  const agentsCard = document.querySelector('.mc-card-link[href="/agents"] .mc-metric')
  setText(
    agentsCard?.querySelector(":scope>p"),
    "Coding agents remain remote-only; local product AI executes only through the governed runtime"
  )
}

function decorateRuntimePolicy() {
  if (document.documentElement.dataset.aiExecutionPolicy !== "split-governance") {
    document.documentElement.dataset.aiExecutionPolicy = "split-governance"
  }
  document.querySelectorAll('a[href="/ai"]').forEach(link => {
    if (link.title !== "AI Governance · remote-only coding · governed local runtime") {
      link.title = "AI Governance · remote-only coding · governed local runtime"
    }
    if (link.closest(".mc-nav-group")) {
      setText(link.querySelector("span:last-child"), "AI Governance")
    }
  })
  decorateDashboardPolicy()
}

function installKeyboardShortcuts() {
  document.addEventListener("keydown", event => {
    const target = event.target
    const typing = target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target?.isContentEditable

    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
      event.preventDefault()
      if (document.documentElement.classList.contains("mc-palette-open")) window.ShadowOpsCommandPalette?.close()
      else window.ShadowOpsCommandPalette?.open()
      return
    }

    if (event.key === "Escape" && document.documentElement.classList.contains("mc-palette-open")) {
      event.preventDefault()
      window.ShadowOpsCommandPalette?.close()
      return
    }

    if (!typing && event.key === "/") {
      event.preventDefault()
      window.ShadowOpsCommandPalette?.open()
    }
  })
}

function bootMissionControlUI() {
  buildCommandPalette()
  installCommandTrigger()
  decorateRuntimePolicy()
}

let decorationQueued = false
const observer = new MutationObserver(() => {
  if (decorationQueued) return
  decorationQueued = true
  requestAnimationFrame(() => {
    decorationQueued = false
    installCommandTrigger()
    decorateRuntimePolicy()
  })
})

bootMissionControlUI()
installKeyboardShortcuts()
observer.observe(document.documentElement, {subtree: true, childList: true})
window.addEventListener("phx:page-loading-stop", bootMissionControlUI)
