const storage = window.localStorage
const $ = (selector, root = document) => root.querySelector(selector)
const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector))

function addStylesheet() {
  if (document.querySelector('link[data-shadowops-v4]')) return
  const link = document.createElement('link')
  link.rel = 'stylesheet'
  link.href = '/assets/mission-control-v4.css'
  link.dataset.shadowopsV4 = 'true'
  document.head.appendChild(link)
}

function applyPreferences() {
  document.body.classList.toggle('mc-density-compact', storage.getItem('shadowops:density') === 'compact')
  document.body.classList.toggle('mc-sidebar-collapsed', storage.getItem('shadowops:sidebar') === 'collapsed')
}

function toggleSidebar() {
  const collapsed = document.body.classList.toggle('mc-sidebar-collapsed')
  storage.setItem('shadowops:sidebar', collapsed ? 'collapsed' : 'expanded')
}

function toggleDensity() {
  const compact = document.body.classList.toggle('mc-density-compact')
  storage.setItem('shadowops:density', compact ? 'compact' : 'comfortable')
}

function closeMobileNav() {
  document.body.classList.remove('mc-mobile-nav-open')
}

function toggleMobileNav() {
  document.body.classList.toggle('mc-mobile-nav-open')
}

function navigationCommands() {
  return $$('.mc-sidebar nav a').map((link) => ({
    label: link.textContent.trim(),
    group: link.closest('.mc-nav-group')?.querySelector('h2')?.textContent.trim() || 'Navigate',
    hint: link.getAttribute('href'),
    run: () => { window.location.href = link.href }
  }))
}

function systemCommands() {
  return [
    {label: 'Refresh current view', group: 'Actions', hint: 'R', run: () => window.location.reload()},
    {label: 'Toggle sidebar', group: 'Appearance', hint: 'S', run: toggleSidebar},
    {label: 'Toggle compact density', group: 'Appearance', hint: 'D', run: toggleDensity},
    {label: 'Open health', group: 'System', hint: '/health', run: () => { window.location.href = '/health' }},
    {label: 'Open readiness', group: 'System', hint: '/ready', run: () => { window.location.href = '/ready' }}
  ]
}

function createPalette() {
  if ($('#mc-command-palette')) return $('#mc-command-palette')

  const dialog = document.createElement('dialog')
  dialog.id = 'mc-command-palette'
  dialog.className = 'mc-palette'
  dialog.innerHTML = `
    <form method="dialog" class="mc-palette-shell" aria-label="ShadowOps command palette">
      <div class="mc-palette-search-row">
        <span class="mc-palette-search-icon" aria-hidden="true">⌕</span>
        <input id="mc-palette-input" class="mc-palette-input" type="search" autocomplete="off" spellcheck="false" placeholder="Navigate or run an action…" aria-label="Search commands" />
        <kbd>Esc</kbd>
      </div>
      <div id="mc-palette-results" class="mc-palette-results" role="listbox" aria-label="Available commands"></div>
      <footer class="mc-palette-footer"><span>↑↓ select</span><span>Enter open</span><span>Ctrl/Cmd K command palette</span></footer>
    </form>`
  document.body.appendChild(dialog)

  const input = $('#mc-palette-input', dialog)
  const results = $('#mc-palette-results', dialog)
  let activeIndex = 0
  let visible = []

  const render = () => {
    const q = input.value.trim().toLowerCase()
    const commands = [...navigationCommands(), ...systemCommands()]
    visible = commands.filter((command) => `${command.group} ${command.label} ${command.hint}`.toLowerCase().includes(q))
    activeIndex = Math.min(activeIndex, Math.max(visible.length - 1, 0))
    results.replaceChildren()

    if (!visible.length) {
      const empty = document.createElement('p')
      empty.className = 'mc-palette-empty'
      empty.textContent = 'No matching command'
      results.appendChild(empty)
      return
    }

    visible.forEach((command, index) => {
      const button = document.createElement('button')
      button.type = 'button'
      button.className = `mc-palette-item${index === activeIndex ? ' is-active' : ''}`
      button.setAttribute('role', 'option')
      button.setAttribute('aria-selected', index === activeIndex ? 'true' : 'false')

      const text = document.createElement('span')
      text.className = 'mc-palette-item-text'
      const group = document.createElement('small')
      group.textContent = command.group
      const label = document.createElement('strong')
      label.textContent = command.label
      text.append(group, label)

      const hint = document.createElement('span')
      hint.className = 'mc-palette-hint'
      hint.textContent = command.hint
      button.append(text, hint)
      button.addEventListener('mouseenter', () => { activeIndex = index; render() })
      button.addEventListener('click', () => { dialog.close(); command.run() })
      results.appendChild(button)
    })
  }

  input.addEventListener('input', () => { activeIndex = 0; render() })
  input.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowDown') {
      event.preventDefault(); activeIndex = Math.min(activeIndex + 1, visible.length - 1); render()
    } else if (event.key === 'ArrowUp') {
      event.preventDefault(); activeIndex = Math.max(activeIndex - 1, 0); render()
    } else if (event.key === 'Enter' && visible[activeIndex]) {
      event.preventDefault(); dialog.close(); visible[activeIndex].run()
    }
  })
  dialog.addEventListener('close', () => { input.value = ''; activeIndex = 0 })
  dialog.addEventListener('click', (event) => {
    if (event.target === dialog) dialog.close()
  })

  dialog.openPalette = () => {
    render()
    if (!dialog.open) dialog.showModal()
    requestAnimationFrame(() => input.focus())
  }

  return dialog
}

function installTopbarControls() {
  const meta = $('.mc-topbar-meta')
  if (!meta || $('[data-mc-v4-controls]', meta)) return

  const controls = document.createElement('div')
  controls.className = 'mc-v4-controls'
  controls.dataset.mcV4Controls = 'true'

  const menu = document.createElement('button')
  menu.type = 'button'
  menu.className = 'mc-icon-button mc-mobile-menu-button'
  menu.setAttribute('aria-label', 'Toggle navigation')
  menu.textContent = '☰'
  menu.addEventListener('click', toggleMobileNav)

  const command = document.createElement('button')
  command.type = 'button'
  command.className = 'mc-command-trigger'
  command.setAttribute('aria-label', 'Open command palette')
  command.innerHTML = '<span>⌕</span><span>Command</span><kbd>⌘K</kbd>'
  command.addEventListener('click', () => createPalette().openPalette())

  controls.append(menu, command)
  meta.prepend(controls)
}

function installMobileBackdrop() {
  if ($('.mc-mobile-backdrop')) return
  const backdrop = document.createElement('button')
  backdrop.type = 'button'
  backdrop.className = 'mc-mobile-backdrop'
  backdrop.setAttribute('aria-label', 'Close navigation')
  backdrop.addEventListener('click', closeMobileNav)
  document.body.appendChild(backdrop)
  $$('.mc-sidebar a').forEach((link) => link.addEventListener('click', closeMobileNav))
}

function installKeyboardShortcuts() {
  document.addEventListener('keydown', (event) => {
    const target = event.target
    const editing = target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement || target?.isContentEditable

    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
      event.preventDefault()
      createPalette().openPalette()
      return
    }

    if (!editing && event.key === '/') {
      event.preventDefault()
      createPalette().openPalette()
      return
    }

    if (!editing && !event.ctrlKey && !event.metaKey && !event.altKey) {
      if (event.key.toLowerCase() === 'r') window.location.reload()
      if (event.key.toLowerCase() === 's') toggleSidebar()
      if (event.key.toLowerCase() === 'd') toggleDensity()
    }
  })
}

function bootV4() {
  addStylesheet()
  applyPreferences()
  createPalette()
  installTopbarControls()
  installMobileBackdrop()
  installKeyboardShortcuts()
  document.documentElement.dataset.shadowopsUi = 'v4'
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', bootV4, {once: true})
else bootV4()
