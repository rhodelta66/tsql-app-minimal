// Pure reading of one screen payload. No card names and no DOM.

const INPUT_TYPES = new Set([
  "text",
  "password",
  "email",
  "number",
  "search",
  "tel",
  "url",
  "date",
  "time",
  "datetime-local",
]);

export function settingsMap(payload) {
  const map = {};
  const rows = payload && payload.settings;
  if (!Array.isArray(rows)) return map;
  for (const row of rows) {
    if (!row || typeof row !== "object") continue;
    const key = row.k ?? row.key;
    if (key == null || key === "") continue;
    map[String(key)] = row.v ?? row.value ?? null;
  }
  return map;
}

export function flag(value) {
  return value === true || value === 1 || value === "1";
}

// A system card is shown when the token claim role matches ide_role.
// A blank ide_role, or is_system 0, does not restrict the card.
export function systemAllowed(isSystem, ideRole, roles) {
  if (!flag(isSystem)) return true;
  const needed = String(ideRole == null ? "" : ideRole)
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
  if (!needed.length) return true;
  const held = new Set(
    (Array.isArray(roles) ? roles : [])
      .filter((role) => typeof role === "string")
      .map((role) => role.trim().toLowerCase())
      .filter(Boolean),
  );
  return needed.some((role) => held.has(role.toLowerCase()));
}

export function systemRoleMessage(ideRole) {
  return "Code editing requires the role " + String(ideRole == null ? "" : ideRole).trim() + ".";
}

export function inputType(value) {
  const name = String(value || "text").toLowerCase();
  return INPUT_TYPES.has(name) ? name : "text";
}

// Modal fields keep a safe control name. Card columns still use inputType.
export function fieldWidget(value) {
  const name = String(value || "text").toLowerCase().trim();
  if (name === "textarea" || name === "select" || name === "radio") return name;
  if (/^[a-z][a-z0-9-]*$/.test(name)) return name;
  return "text";
}

export function optionsFrom(value) {
  if (!Array.isArray(value)) return [];
  return value.map((row) => {
    if (row && typeof row === "object") {
      const id = row.id == null ? "" : String(row.id);
      const name = row.name == null || String(row.name) === "" ? id : String(row.name);
      return { id, name };
    }
    const text = row == null ? "" : String(row);
    return { id: text, name: text };
  }).filter((row) => row.id !== "");
}

export function fieldInput(typ) {
  const raw = String(typ || "").toLowerCase().trim();
  if (/^(nvarchar|varchar|varbinary)\s*\(\s*max\s*\)$/.test(raw)) return "textarea";
  const name = raw.replace(/\(.*$/, "").trim();
  if (["int", "bigint", "smallint", "tinyint", "decimal", "numeric", "float", "real", "money", "smallmoney"].includes(name)) {
    return "number";
  }
  if (name === "bit") return "checkbox";
  if (name === "date") return "date";
  if (name === "datetime" || name === "datetime2" || name === "time" || name === "datetimeoffset") {
    return "datetime-local";
  }
  return "text";
}

// Button code is the max field named sql. Other max text stays a textarea.
export function fieldEditor(name, typ) {
  if (fieldInput(typ) !== "textarea") return null;
  if (String(name || "").toLowerCase() !== "sql") return null;
  return "sql";
}

export function classTokens(value) {
  return String(value || "")
    .split(/\s+/)
    .filter((token) => /^[A-Za-z_][A-Za-z0-9_-]*$/.test(token));
}

export function pathParts(pathname) {
  const bare = String(pathname || "/").split("?")[0];
  return bare
    .split("/")
    .filter(Boolean)
    .map((part) => {
      try {
        return decodeURIComponent(part);
      } catch {
        return part;
      }
    });
}

export function recordId(pathname) {
  const parts = pathParts(pathname);
  if (parts.length >= 4) return parts[3];
  if (parts.length === 3) return null;
  return parts.length >= 2 ? parts[1] : null;
}

function rowId(row, idColumn) {
  if (!row || row[idColumn] == null || String(row[idColumn]) === "") return null;
  return row[idColumn];
}

// The list cursor is one primary key. Keep the pointed-at row when it is still
// on screen. Otherwise point at the first row. An empty list has no cursor.
export function cursorOn(rows, idColumn, selectedId) {
  const column = idColumn || "id";
  const list = Array.isArray(rows) ? rows : [];
  if (selectedId != null && String(selectedId) !== "") {
    const match = list.find((row) => String(rowId(row, column)) === String(selectedId));
    if (match) return rowId(match, column);
  }
  const first = list.find((row) => rowId(row, column) != null);
  return first ? rowId(first, column) : null;
}

export function moveCursor(rows, idColumn, selectedId, step) {
  const column = idColumn || "id";
  const list = (Array.isArray(rows) ? rows : []).filter((row) => rowId(row, column) != null);
  if (!list.length) return null;
  const index = list.findIndex((row) => String(rowId(row, column)) === String(selectedId));
  if (index < 0) return rowId(list[0], column);
  const next = Math.min(list.length - 1, Math.max(0, index + step));
  return rowId(list[next], column);
}

// A list keeps its cursor only for that same list address. A form's cursor is
// the open record. A new form leaves the list cursor alone. A menu clears it.
export function cursorFor(screen) {
  const kind = screen && screen.kind;
  const base = screen && screen.base != null ? screen.base : "";
  const cursorBase = screen && screen.cursorBase != null ? screen.cursorBase : "";
  const selectedId = screen ? screen.selectedId : null;
  if (kind === "list") {
    const keep = cursorBase === base ? selectedId : null;
    return {
      selectedId: cursorOn(screen.rows, screen.idColumn, keep),
      cursorBase: base,
    };
  }
  if (kind === "form") {
    const pathId = screen.pathId;
    if (pathId != null && String(pathId) !== "" && !/^new$/i.test(String(pathId))) {
      return { selectedId: pathId, cursorBase: base };
    }
    return { selectedId, cursorBase };
  }
  return { selectedId: null, cursorBase: "" };
}

// List and form URLs for the card currently on screen. A related list keeps
// the parent prefix, so opening a row stays inside that relation.
export function cardBase(pathname) {
  const parts = pathParts(pathname);
  if (parts.length >= 3) return "/" + parts.slice(0, 3).join("/");
  if (parts.length >= 1) return "/" + parts[0];
  return "";
}

export function relationsFrom(payload) {
  const rows = Array.isArray(payload && payload.relations) ? payload.relations : [];
  return rows
    .filter((row) => row && row.name && !flag(row.is_hidden))
    .map((row) => ({
      name: String(row.name),
      label: row.disp || row.name,
      keycode: row.keycode || "",
      unbound: flag(row.unbound),
    }));
}

// Bound needs a real record. Unbound uses "-" when nothing is selected.
// The server turns that path into the child list. No concrete path is stored
// on the relation, because the selected row is client state.
export function relationTarget(card, pathname, selectedId, relation) {
  if (!card || !relation || !relation.name) return null;
  const current = recordId(pathname);
  const chosen = current != null ? current : selectedId;
  const usable = chosen != null && chosen !== "" && !/^new$/i.test(String(chosen));
  if (relation.unbound) {
    return "/" + card + "/" + (usable ? String(chosen) : "-") + "/" + relation.name;
  }
  if (!usable) return null;
  return "/" + card + "/" + String(chosen) + "/" + relation.name;
}

export function headingTag(className) {
  const tokens = classTokens(className);
  if (tokens.includes("h1")) return "h1";
  if (tokens.includes("h2")) return "h2";
  if (tokens.includes("h3")) return "h3";
  return "p";
}

function columnsFrom(def) {
  return (Array.isArray(def) ? def : [])
    .filter((field) => field && field.name && !flag(field.is_hid))
    .map((field) => ({
      name: String(field.name),
      label: field.disp || field.name,
      cls: classTokens(field.cls).join(" "),
      editable: flag(field.is_upd) && !flag(field.is_id),
      input: fieldInput(field.typ),
      editor: fieldEditor(field.name, field.typ),
    }));
}

function columnsFromRows(rows) {
  const names = [];
  for (const row of rows) {
    if (!row || typeof row !== "object") continue;
    for (const key of Object.keys(row)) {
      if (!names.includes(key)) names.push(key);
    }
  }
  return names.map((name) => ({ name, label: name, cls: "", editable: false, input: "text" }));
}

export function crumbsFrom(payload) {
  const rows = Array.isArray(payload && payload.breadcrumbs) ? payload.breadcrumbs : [];
  const items = rows.map((row) => ({
    label: (row && (row.disp || row.name || row.card_name)) || "Page",
    pathname: (row && (row.pathname || row.path)) || "/",
    search: (row && row.search) || "",
  }));
  if (!items.length || items[0].pathname !== "/") {
    items.unshift({ label: "Home", pathname: "/", search: "" });
  }
  return items;
}

export function actionsFrom(payload) {
  const rows = Array.isArray(payload && payload.actions) ? payload.actions : [];
  return rows
    .filter((row) => row && row.name && !String(row.type || "").toLowerCase().includes("hidden"))
    .map((row) => ({
      name: String(row.name),
      label: row.disp || row.name,
      keycode: row.keycode || "",
      kind: row.action || "",
      pathname: row.params && row.params.pathname ? String(row.params.pathname) : "",
    }));
}

export function controlFrom(control) {
  const kind = control && control.kind;
  if (kind === "text") {
    return {
      kind: "text",
      text: control.text == null ? "" : String(control.text),
      className: classTokens(control.class).join(" "),
      tag: headingTag(control.class),
    };
  }
  if (kind === "input") {
    const type = fieldWidget(control.type);
    const options = optionsFrom(control.options);
    let value = control.value == null ? "" : String(control.value);
    if (type === "checkbox" && !options.length) {
      const mark = value.toLowerCase();
      value = mark === "1" || mark === "true" || mark === "on" ? "1" : "0";
    }
    return {
      kind: "input",
      name: control.name == null ? "" : String(control.name),
      type,
      value,
      placeholder: control.placeholder == null ? "" : String(control.placeholder),
      focus: flag(control.focus),
      label: control.label == null ? "" : String(control.label),
      options,
      multiple: flag(control.multiple),
    };
  }
  if (kind === "button") {
    return {
      kind: "button",
      name: control.name == null ? "" : String(control.name),
      value: control.value == null ? "" : String(control.value),
      className: classTokens(control.class).join(" "),
      key: control.key == null ? "" : String(control.key),
    };
  }
  if (kind === "modal") {
    return { kind: "modal", className: classTokens(control.class).join(" ") };
  }
  return {
    kind: "unknown",
    text: safeJson(control),
  };
}

function safeJson(value) {
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

export function modalFrom(payload, values, roles) {
  const modal = payload && payload.modal;
  if (!modal || !Array.isArray(modal.controls) || modal.controls.length === 0) return null;
  const controls = modal.controls.map(controlFrom).filter((control) => control.kind !== "modal");
  if (values) {
    for (const control of controls) {
      if (control.kind === "input" && Object.prototype.hasOwnProperty.call(values, control.name)) {
        control.value = values[control.name] == null ? "" : String(values[control.name]);
      }
    }
  }
  let edit = typeof modal.edit === "string" && /^\/[A-Za-z0-9_/-]+$/.test(modal.edit) ? modal.edit : "";
  if (edit && !systemAllowed(modal.is_system, modal.ide_role, roles)) edit = "";
  return {
    className: classTokens(modal.class).join(" "),
    controls,
    edit,
  };
}

export function screenFrom(payload, options = {}) {
  const body = payload && typeof payload === "object" ? payload : {};
  const settings = settingsMap(body);
  const roles = options.roles || [];
  const allowed = systemAllowed(settings.is_system, settings.ide_role, roles);
  const source = allowed && Array.isArray(body.data) ? body.data : [];
  let columns = allowed ? columnsFrom(body.def) : [];
  const isForm = flag(settings.is_form);
  let kind = "empty";
  if (columns.length && isForm) kind = "form";
  else if (columns.length) kind = "list";
  else if (source.length && source.every((row) => row && typeof row === "object" && "name" in row)) kind = "menu";
  else if (source.length) {
    kind = "list";
    columns = columnsFromRows(source);
  }
  const menu = kind === "menu"
    ? source
      .filter((row) => systemAllowed(row.is_system, row.ide_role, roles))
      .map((row) => ({
        name: String(row.name),
        label: row.disp || row.name,
        keycode: row.keycode || "",
        pathname: "/" + String(row.name),
      }))
    : [];
  let error = body.error ? String(body.error) : "";
  if (!allowed && !error) error = systemRoleMessage(settings.ide_role);
  return {
    kind,
    title: settings.cardname || (kind === "menu" ? "Home" : "Screen"),
    user: settings.user || "",
    card: settings.cardname || "",
    idColumn: settings.id_column || "id",
    error,
    crumbs: crumbsFrom(body),
    actions: allowed ? actionsFrom(body) : [],
    relations: allowed ? relationsFrom(body) : [],
    columns,
    rows: source,
    canDelete: allowed && flag(settings.can_delete),
    menu,
    modal: flag(body.cleared) ? null : modalFrom(body, options.values || null, roles),
    toasts: (Array.isArray(body.toasts) ? body.toasts : []).map((toast) => ({
      text: toast && toast.text != null ? String(toast.text) : "",
      className: classTokens(toast && toast.class).join(" "),
    })),
  };
}

export function modalPosted(controls, values, button) {
  const posted = {};
  for (const control of controls || []) {
    if (control.kind === "input" && control.name) {
      posted[control.name] = values && values[control.name] != null ? String(values[control.name]) : "";
    }
  }
  if (button && button.name) posted[button.name] = button.value == null ? "" : String(button.value);
  return posted;
}

export function fieldString(column, raw) {
  if (column && column.input === "checkbox") {
    if (raw === true || raw === 1 || raw === "1") return "1";
    if (typeof raw === "string" && raw.toLowerCase() === "true") return "1";
    return "0";
  }
  if (raw == null) return "";
  const text = String(raw);
  if (column && column.input === "datetime-local") {
    const match = text.match(/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2})/);
    return match ? match[1] : text;
  }
  return text;
}

export function formValuesFrom(screen) {
  const values = {};
  const record = (screen && screen.rows && screen.rows[0]) || {};
  for (const column of (screen && screen.columns) || []) {
    if (!column.editable) continue;
    values[column.name] = fieldString(column, record[column.name]);
  }
  return values;
}

export function saveExtra(pathname, values) {
  const id = recordId(pathname);
  const creating = id != null && /^new$/i.test(String(id));
  return {
    save: true,
    delete: false,
    values: values || {},
    posted: {},
    action: null,
    id: creating ? null : id,
  };
}

export function deleteExtra(pathname) {
  return {
    save: false,
    delete: true,
    values: null,
    posted: {},
    action: null,
    id: recordId(pathname),
  };
}

export function valuesFrom(controls) {
  const values = {};
  for (const control of controls || []) {
    if (control.kind === "input" && control.name) values[control.name] = control.value ?? "";
  }
  return values;
}

export function matchKey(event, keycode) {
  if (!keycode || !event) return false;
  const parts = String(keycode)
    .split("+")
    .map((part) => part.trim().toLowerCase())
    .filter(Boolean);
  const needAlt = parts.includes("alt");
  const needCtrl = parts.includes("ctrl") || parts.includes("control");
  const needShift = parts.includes("shift");
  const key = parts.find((part) => !["alt", "ctrl", "control", "shift", "meta"].includes(part));
  if (!key) return false;
  if (Boolean(event.altKey) !== needAlt) return false;
  if (Boolean(event.ctrlKey) !== needCtrl) return false;
  if (Boolean(event.shiftKey) !== needShift) return false;
  if (event.metaKey) return false;
  const pressed = String(event.key || "").toLowerCase();
  if (key === "enter") return pressed === "enter";
  if (key === "esc" || key === "escape") return pressed === "escape";
  if (key === "space") return pressed === " " || pressed === "spacebar";
  return pressed === key;
}

export function publicPayload(payload) {
  if (!payload || typeof payload !== "object") return payload;
  const copy = { ...payload };
  delete copy.session;
  return copy;
}
