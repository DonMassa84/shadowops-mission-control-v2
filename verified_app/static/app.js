let workflows = [];
let selected = null;

const list =
  document.querySelector("#workflowList");

const search =
  document.querySelector("#search");

const count =
  document.querySelector("#workflowCount");

const executionCount =
  document.querySelector("#executionCount");

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

async function load() {
  const response = await fetch(
    "/api/workflows",
    {
      cache: "no-store"
    }
  );

  const data = await response.json();

  workflows = data.workflows || [];

  count.textContent =
    workflows.length;

  executionCount.textContent =
    workflows.filter(
      w => w.execution_verified
    ).length;

  render();
}

function render() {
  const q =
    search.value
      .toLowerCase()
      .trim();

  const rows =
    workflows.filter(w =>
      w.name
        .toLowerCase()
        .includes(q)
      ||
      w.id
        .toLowerCase()
        .includes(q)
    );

  list.innerHTML =
    rows.map(w => `
      <div
        class="workflow ${
          selected?.id === w.id
          ? "selected"
          : ""
        }"
        data-id="${escapeHtml(w.id)}"
      >
        <strong>
          ${escapeHtml(w.name)}
        </strong>

        <code>
          ${escapeHtml(w.id)}
        </code>

        <div class="tags">

          <span class="tag">
            DEFINITION VERIFIED
          </span>

          <span class="tag ${
            w.execution_verified
            ? ""
            : "blocked"
          }">
            ${
              w.execution_verified
              ? "E2E VERIFIED"
              : "EXECUTION BLOCKED"
            }
          </span>

        </div>
      </div>
    `).join("");

  document
    .querySelectorAll(".workflow")
    .forEach(el => {

      el.addEventListener(
        "click",
        () => selectWorkflow(
          el.dataset.id
        )
      );

    });
}

function selectWorkflow(id) {
  selected =
    workflows.find(
      w => w.id === id
    );

  if (!selected) return;

  document.querySelector(
    "#emptyState"
  ).hidden = true;

  document.querySelector(
    "#detailState"
  ).hidden = false;

  document.querySelector(
    "#detailName"
  ).textContent =
    selected.name;

  document.querySelector(
    "#detailId"
  ).textContent =
    selected.id;

  document.querySelector(
    "#definitionStatus"
  ).textContent =
    selected.definition_verified
    ? "VERIFIED"
    : "UNKNOWN";

  document.querySelector(
    "#executionStatus"
  ).textContent =
    selected.execution_verified
    ? "VERIFIED"
    : "NOT VERIFIED";

  document.querySelector(
    "#riskStatus"
  ).textContent =
    selected.risk || "UNKNOWN";

  const button =
    document.querySelector(
      "#startButton"
    );

  if (
    selected.start_enabled
    &&
    selected.execution_verified
  ) {
    button.disabled = false;
    button.classList.add(
      "enabled"
    );

    button.textContent =
      "▶ Start verified workflow";

  } else {
    button.disabled = false;
    button.classList.remove(
      "enabled"
    );

    button.textContent =
      "Execution not yet verified";
  }

  document.querySelector(
    "#result"
  ).textContent = "";

  render();
}

document.querySelector(
  "#startButton"
).addEventListener(
  "click",
  async () => {

    if (!selected) return;

    const output =
      document.querySelector(
        "#result"
      );

    output.textContent =
      "Starting governed workflow…";

    const response =
      await fetch(
        `/api/workflows/${
          encodeURIComponent(
            selected.id
          )
        }/start`,
        {
          method: "POST"
        }
      );

    const payload =
      await response.json();

    output.textContent =
      JSON.stringify(
        payload,
        null,
        2
      );

    if (
      response.ok
      &&
      payload.status === "SUCCESS"
    ) {
      output.textContent =
        "✓ WORKFLOW SUCCESS\n\n"
        + JSON.stringify(
            payload,
            null,
            2
          );
    }
  }
);

search.addEventListener(
  "input",
  render
);

load().catch(error => {
  list.innerHTML =
    `<div class="workflow">
      LOAD FAILED:
      ${escapeHtml(error.message)}
    </div>`;
});
