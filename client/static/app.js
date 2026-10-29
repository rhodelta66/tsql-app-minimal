const state = {
  session: localStorage.getItem("tsql.session") || null,
  pathname: "/",
  selectedId: null,
  payload: null,
  modalValues: {},
};

const screen = document.querySelector("#screen");
const toolbar = document.querySelector("#toolbar");
const crumbs = document.querySelector("#crumbs");
const title = document.querySelector("#title");
const who = document.querySelector("#who");
const errorBox = document.querySelector("#error");
const toastBox = document.querySelector("#toasts");
const modal = document.querySelector("#modal");
const jsonBox = document.querySelector("#json");

function setting(key) {
  const row = (state.payload?.settings || []).find((item) => item.key === key);
  return row ? row.value : null;
}

function mainView() {
  const views = state.payload?.views || [];
  return views.find((view) => view.comp === "Listview" || view.comp === "Form" || view.comp === "Menu") || null;
}

function rowId(row) {
  const key = setting("id_column") || "id";
  return row[key];
}

async function callServer(body) {
  const response = await fetch("/api/request", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error || "Request failed");
  }
  return payload;
}

async function go(options = {}) {
  const pathname = options.pathname ?? state.pathname;
  const payload = await callServer({
    session: state.session,
    pathname,
    action: options.action || null,
    posted: options.posted || {},
    id: options.id === undefined ? state.selectedId : options.id,
    ids: options.ids === undefined ? (state.selectedId != null ? String(state.selectedId) : null) : options.ids,
    close: Boolean(options.close),
  });
  state.session = payload.session || state.session;
  if (state.session) localStorage.setItem("tsql.session", state.session);
  state.pathname = pathname;
  state.payload = payload;
  if (payload.cleared) state.modalValues = {};
  render();
}

function visibleFields() {
  return (state.payload?.def || []).filter((field) => !field.is_hid);
}

function actionVisible(action, comp) {
  const type = (action.type || "").toLowerCase();
  if (type.includes("hidden") || type === "modal_only") return false;
  if (comp === "Listview") return type === "list" || type === "list_form" || type === "";
  if (comp === "Form") return type === "form" || type === "list_form" || type === "";
  return false;
}

function renderCrumbs() {
  crumbs.replaceChildren();
  (state.payload?.breadcrumbs || []).forEach((crumb, index, all) => {
    if (index > 0) crumbs.append(" / ");
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = crumb.name;
    button.addEventListener("click", () => {
      state.selectedId = null;
      go({ pathname: crumb.path, action: null, posted: {}, id: null, ids: null });
    });
    crumbs.append(button);
    if (index === all.length - 1) button.disabled = true;
  });
}

function renderToolbar(comp) {
  toolbar.replaceChildren();
  (state.payload?.actions || []).filter((action) => actionVisible(action, comp)).forEach((action) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "action " + ((action.params && action.params.className) || "");
    button.textContent = action.disp || action.name;
    if (action.keycode) button.title = action.keycode;
    button.addEventListener("click", () => runAction(action));
    toolbar.append(button);
  });
}

function runAction(action) {
  if (action.action === "pathname" && action.params && action.params.pathname) {
    go({ pathname: action.params.pathname, action: null, posted: {}, id: null });
    return;
  }
  go({
    pathname: state.pathname,
    action: action.name,
    posted: {},
    id: state.selectedId,
  });
}

function renderMenu() {
  const wrap = document.createElement("div");
  wrap.className = "menu";
  const rows = Array.isArray(state.payload.data) ? state.payload.data : [];
  if (!rows.length) {
    wrap.innerHTML = '<p class="empty">No cards in the main menu.</p>';
  }
  rows.forEach((row) => {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = row.name + (row.keycode ? " (" + row.keycode + ")" : "");
    button.addEventListener("click", () => go({ pathname: row.path, action: null, posted: {}, id: null }));
    wrap.append(button);
  });
  screen.replaceChildren(wrap);
}

function renderList() {
  const fields = visibleFields();
  const rows = Array.isArray(state.payload.data) ? state.payload.data : [];
  const table = document.createElement("table");
  const head = document.createElement("tr");
  fields.forEach((field) => {
    const cell = document.createElement("th");
    cell.textContent = field.disp || field.name;
    if (field.cls) cell.className = field.cls;
    head.append(cell);
  });
  const thead = document.createElement("thead");
  thead.append(head);
  const body = document.createElement("tbody");
  rows.forEach((row) => {
    const tr = document.createElement("tr");
    const id = rowId(row);
    if (String(id) === String(state.selectedId)) tr.className = "selected";
    tr.addEventListener("click", () => {
      state.selectedId = id;
      render();
    });
    tr.addEventListener("dblclick", () => {
      state.selectedId = id;
      const card = setting("cardname");
      go({ pathname: "/" + card + "/" + id, action: null, posted: {}, id });
    });
    fields.forEach((field) => {
      const cell = document.createElement("td");
      const value = row[field.name];
      cell.textContent = value == null ? "" : String(value);
      if (field.cls) cell.className = field.cls;
      tr.append(cell);
    });
    body.append(tr);
  });
  if (!rows.length) {
    const tr = document.createElement("tr");
    const cell = document.createElement("td");
    cell.colSpan = Math.max(fields.length, 1);
    cell.className = "empty";
    cell.textContent = "No rows.";
    tr.append(cell);
    body.append(tr);
  }
  table.append(thead, body);
  const hint = document.createElement("p");
  hint.className = "empty";
  hint.textContent = "Click a row to select it. Double-click to open the form. Note and Wizard use the selection.";
  screen.replaceChildren(table, hint);
}

function renderForm() {
  const fields = visibleFields();
  const rows = Array.isArray(state.payload.data) ? state.payload.data : [];
  const row = rows[0] || {};
  const grid = document.createElement("div");
  grid.className = "form-grid";
  if (!rows.length) {
    grid.innerHTML = '<p class="empty">No record.</p>';
  }
  fields.forEach((field) => {
    const label = document.createElement("div");
    label.className = "label";
    label.textContent = field.disp || field.name;
    const value = document.createElement("div");
    const raw = row[field.name];
    value.textContent = raw == null ? "" : String(raw);
    grid.append(label, value);
  });
  screen.replaceChildren(grid);
}

function controlByKind(kind) {
  return (state.payload?.modal?.controls || []).filter((control) => control.kind === kind);
}

function renderModal() {
  const dialog = state.payload?.modal;
  if (!dialog || !dialog.controls) {
    modal.hidden = true;
    modal.replaceChildren();
    return;
  }
  state.modalValues = {};
  dialog.controls.forEach((control) => {
    if (control.kind === "input") state.modalValues[control.name] = control.value ?? "";
  });

  const card = document.createElement("form");
  card.className = "modal-card " + (dialog.class || "");
  const body = document.createElement("div");
  const actions = document.createElement("div");
  actions.className = "modal-actions";

  dialog.controls.forEach((control) => {
    if (control.kind === "text") {
      const node = document.createElement(control.class === "h3" || control.class === "h2" ? "h3" : "p");
      node.className = control.class || "text";
      node.textContent = control.text || "";
      body.append(node);
    } else if (control.kind === "input") {
      const label = document.createElement("label");
      const input = document.createElement("input");
      input.type = control.type || "text";
      input.name = control.name;
      input.placeholder = control.placeholder || "";
      input.value = state.modalValues[control.name] ?? "";
      input.addEventListener("input", () => {
        state.modalValues[control.name] = input.value;
      });
      label.append(input);
      body.append(label);
    } else if (control.kind === "button") {
      const button = document.createElement("button");
      button.type = "button";
      button.className = control.class || "";
      button.textContent = control.value || control.name;
      if (control.key) button.title = control.key;
      button.addEventListener("click", () => submitModal(control));
      actions.append(button);
    }
  });

  card.append(body, actions);
  card.addEventListener("submit", (event) => {
    event.preventDefault();
    const enter = (dialog.controls || []).find((control) => control.kind === "button" && control.key === "Enter");
    if (enter) submitModal(enter);
  });
  modal.replaceChildren(card);
  modal.hidden = false;
  const focus = card.querySelector("input");
  if (focus) focus.focus();
}

function submitModal(button) {
  const posted = { ...state.modalValues };
  posted[button.name] = button.value;
  go({ pathname: state.pathname, action: null, posted, id: state.selectedId });
}

function renderToasts() {
  toastBox.replaceChildren();
  (state.payload?.toasts || []).forEach((toast) => {
    const node = document.createElement("div");
    node.className = "toast " + (toast.class || "");
    node.textContent = toast.text || "";
    toastBox.append(node);
  });
}

function render() {
  const payload = state.payload || {};
  const view = mainView();
  const comp = view ? view.comp : "Menu";
  title.textContent = setting("cardname") || (comp === "Menu" ? "Menu" : state.pathname);
  who.textContent = setting("user") || "";
  if (payload.error) {
    errorBox.hidden = false;
    errorBox.textContent = payload.error;
  } else {
    errorBox.hidden = true;
    errorBox.textContent = "";
  }
  renderCrumbs();
  renderToolbar(comp);
  if (comp === "Menu") renderMenu();
  else if (comp === "Form") renderForm();
  else renderList();
  renderModal();
  renderToasts();
  jsonBox.textContent = JSON.stringify(payload, null, 2);
}

function matchKey(event, keycode) {
  if (!keycode) return false;
  const parts = keycode.split("+").map((part) => part.toLowerCase());
  const needAlt = parts.includes("alt");
  const needCtrl = parts.includes("ctrl");
  const needShift = parts.includes("shift");
  const key = parts.filter((part) => !["alt", "ctrl", "shift"].includes(part))[0];
  if (Boolean(event.altKey) !== needAlt || Boolean(event.ctrlKey) !== needCtrl || Boolean(event.shiftKey) !== needShift) {
    return false;
  }
  if (key === "enter") return event.key === "Enter";
  if (key === "esc" || key === "escape") return event.key === "Escape";
  return event.key.toLowerCase() === key;
}

document.addEventListener("keydown", (event) => {
  const modalOpen = state.payload && state.payload.modal;
  if (modalOpen && event.key === "Escape") {
    const esc = (state.payload.modal.controls || []).find((control) =>
      control.kind === "button" && (control.key === "Esc" || control.key === "Escape"));
    if (esc) submitModal(esc);
    else go({ pathname: state.pathname, action: null, posted: {}, close: true });
    event.preventDefault();
    return;
  }
  if (event.target && (event.target.tagName === "INPUT" || event.target.tagName === "TEXTAREA")) return;
  const comp = mainView()?.comp;
  const action = (state.payload?.actions || []).find((item) => matchKey(event, item.keycode) && actionVisible(item, comp));
  if (action) {
    event.preventDefault();
    runAction(action);
    return;
  }
  if (!modalOpen && event.key === "Enter" && state.selectedId != null && comp === "Listview") {
    const card = setting("cardname");
    go({ pathname: "/" + card + "/" + state.selectedId, action: null, posted: {}, id: state.selectedId });
  }
});

go({ pathname: "/", action: null, posted: {}, id: null }).catch((error) => {
  errorBox.hidden = false;
  errorBox.textContent = error.message;
});
