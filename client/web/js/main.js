import { screen } from "./api.js";
import { claimName, clear, expiring, load, login, refresh, rolesFromAccess, verify } from "./auth.js";
import { accountPath, discover } from "./config.js";
import { cardBase, cursorFor, deleteExtra, formValuesFrom, matchKey, modalPosted, moveCursor, publicPayload, recordId, relationTarget, saveExtra, screenFrom, valuesFrom } from "./contract.js";
import { paint } from "./view.js";

const config = discover();
const root = document.querySelector("#app");

const state = {
  mode: "login",
  needs2fa: false,
  username: "",
  pathname: window.location.pathname || "/",
  search: window.location.search || "",
  selectedId: null,
  cursorBase: "",
  payload: null,
  model: emptyModel(),
  values: {},
  formValues: {},
  busy: false,
  error: "",
  who: "",
  payloadText: "",
  session: null,
};

let generation = 0;

function emptyModel() {
  return screenFrom({});
}

function currentId() {
  return recordId(state.pathname) ?? (state.selectedId == null ? null : state.selectedId);
}

function callerRoles() {
  return rolesFromAccess(state.session && state.session.access);
}

function adopt(payload) {
  state.payload = payload;
  state.model = screenFrom(payload, { roles: callerRoles() });
  state.values = valuesFrom(state.model.modal && state.model.modal.controls);
  state.formValues = formValuesFrom(state.model);
  state.payloadText = JSON.stringify(publicPayload(payload), null, 2);
  const creating = /^new$/i.test(recordId(state.pathname) || "");
  const savedRow = state.model.rows[0];
  const savedId = savedRow && savedRow[state.model.idColumn];
  if (creating && state.model.kind === "form" && state.model.card && !state.model.error && savedId != null && String(savedId) !== "") {
    const next = cardBase(state.pathname) + "/" + savedId;
    if (next !== state.pathname) {
      window.history.replaceState({}, "", next + (state.search || ""));
      state.pathname = next;
    }
  }
  state.who = state.model.user || claimName(state.session && state.session.access) || "";
}

function placeCursor() {
  const placed = cursorFor({
    kind: state.model.kind,
    base: cardBase(state.pathname),
    cursorBase: state.cursorBase,
    selectedId: state.selectedId,
    rows: state.model.rows,
    idColumn: state.model.idColumn,
    pathId: recordId(state.pathname),
  });
  state.selectedId = placed.selectedId;
  state.cursorBase = placed.cursorBase;
}

function render() {
  if (state.payload) state.model = screenFrom(state.payload, { values: state.values, roles: callerRoles() });
  paint(root, state, handlers);
}

async function liveSession() {
  let session = state.session || load();
  if (!session) return null;
  if (expiring(session)) {
    session = await refresh(config.auth, session);
    if (!session) {
      clear();
      state.session = null;
      return null;
    }
  }
  state.session = session;
  return session;
}

async function loadScreen(extra = {}) {
  if (state.busy) return;
  const gen = ++generation;
  state.mode = "screen";
  state.busy = true;
  state.error = "";
  render();
  try {
    const session = await liveSession();
    if (!session) {
      if (gen !== generation) return;
      state.busy = false;
      showLogin("Sign in to continue.");
      return;
    }
    const id = extra.id === undefined ? currentId() : extra.id;
    const payload = await screen(config.api, session.access, {
      pathname: (extra.pathname || state.pathname) + (extra.search == null ? state.search : extra.search),
      posted: extra.posted || {},
      action: extra.action || null,
      id,
      ids: id == null ? null : String(id),
      close: Boolean(extra.close),
      save: Boolean(extra.save),
      delete: Boolean(extra.delete),
      values: extra.values || null,
    });
    if (gen !== generation) return;
    adopt(payload);
    if (extra.delete && !state.model.error) {
      const next = cardBase(extra.pathname || state.pathname);
      if (next && next !== state.pathname) {
        window.history.replaceState({}, "", next + (state.search || ""));
        state.pathname = next;
      }
    }
    placeCursor();
    state.busy = false;
    render();
  } catch (error) {
    if (gen !== generation) return;
    state.busy = false;
    if (error.status === 401) {
      clear();
      state.session = null;
      showLogin("The session ended. Sign in again.");
      return;
    }
    state.error = error.message || "Request failed";
    render();
  }
}

function navigate(pathname, search) {
  const next = pathname || "/";
  const query = search || "";
  const url = next + query;
  if (url !== window.location.pathname + window.location.search) {
    window.history.pushState({}, "", url);
  }
  state.pathname = next;
  state.search = query;
  loadScreen({ pathname: next, search: query, posted: {}, action: null, id: recordId(next), close: false });
}

function showLogin(message) {
  state.mode = "login";
  state.error = message || "";
  state.busy = false;
  document.title = "Sign in · tsql";
  render();
}

const handlers = {
  get formValues() {
    return state.formValues;
  },
  get selectedId() {
    return state.selectedId;
  },
  get pathname() {
    return state.pathname;
  },
  navigate,
  action(action) {
    if (state.busy) return;
    if (action.kind === "pathname" && action.pathname) {
      navigate(action.pathname, "");
      return;
    }
    loadScreen({ action: action.name, posted: {}, id: currentId() });
  },
  select(id) {
    state.selectedId = id;
    render();
  },
  open(id) {
    if (id == null || id === "") return;
    const base = cardBase(state.pathname);
    if (!base) return;
    state.selectedId = id;
    navigate(base + "/" + id, "");
  },
  openNew() {
    const base = cardBase(state.pathname);
    if (!base) return;
    navigate(base + "/new", "");
  },
  relation(relation) {
    const target = relationTarget(state.model.card, state.pathname, state.selectedId, relation);
    if (!target) return;
    navigate(target, "");
  },
  formInput(name, value) {
    state.formValues[name] = value;
  },
  save() {
    if (state.busy || state.model.kind !== "form") return;
    if (!state.model.columns.some((column) => column.editable)) return;
    loadScreen(saveExtra(state.pathname, { ...state.formValues }));
  },
  remove() {
    if (state.busy || state.model.kind !== "form" || !state.model.canDelete) return;
    const id = recordId(state.pathname);
    if (id == null || /^new$/i.test(String(id))) return;
    if (!window.confirm("Delete this record?")) return;
    loadScreen(deleteExtra(state.pathname));
  },
  modalInput(name, value) {
    state.values[name] = value;
  },
  modalButton(control) {
    if (state.busy || !state.model.modal) return;
    const posted = modalPosted(state.model.modal.controls, state.values, control);
    loadScreen({ posted, action: null, id: currentId() });
  },
  close() {
    loadScreen({ posted: {}, action: null, close: true, id: currentId() });
  },
  escape() {
    if (!state.model.modal) return;
    const esc = state.model.modal.controls.find((control) =>
      control.kind === "button" && /^(esc|escape)$/i.test(control.key));
    if (esc) handlers.modalButton(esc);
    else handlers.close();
  },
  logout() {
    generation += 1;
    clear();
    state.session = null;
    state.payload = null;
    state.needs2fa = false;
    showLogin("");
  },
  async login(username, password) {
    state.error = "";
    state.username = username;
    state.busy = true;
    render();
    try {
      const result = await login(config.auth, username, password);
      state.busy = false;
      if (result.needs2fa) {
        state.needs2fa = true;
        state.error = "";
        render();
        return;
      }
      if (result.error) {
        state.error = result.error;
        render();
        return;
      }
      state.session = result.session;
      state.needs2fa = false;
      loadScreen({ posted: {}, action: null, id: recordId(state.pathname) });
    } catch (error) {
      state.busy = false;
      state.error = error.message || "Sign-in failed";
      render();
    }
  },
  async verify(code) {
    state.busy = true;
    state.error = "";
    render();
    try {
      const result = await verify(config.auth, state.username, code);
      state.busy = false;
      if (result.error) {
        state.error = result.error;
        render();
        return;
      }
      state.session = result.session;
      state.needs2fa = false;
      loadScreen({ posted: {}, action: null, id: recordId(state.pathname) });
    } catch (error) {
      state.busy = false;
      state.error = error.message || "Sign-in failed";
      render();
    }
  },
};

function onKey(event) {
  if (state.mode !== "screen" || !state.payload || state.busy) return;
  if (state.model.modal) return;
  const typing = event.target && /^(INPUT|TEXTAREA|SELECT)$/.test(event.target.tagName);
  const formField = typing && event.target.closest && event.target.closest(".form");
  const commandSave = (event.ctrlKey || event.metaKey) && String(event.key || "").toLowerCase() === "s";
  const enterSave = event.key === "Enter" && formField && event.target.tagName !== "TEXTAREA";
  if (state.model.kind === "form" && (commandSave || enterSave)) {
    event.preventDefault();
    handlers.save();
    return;
  }
  if (typing) return;
  const plainArrows = !event.altKey && !event.ctrlKey && !event.metaKey;
  if (plainArrows && state.model.kind === "list" && (event.key === "ArrowDown" || event.key === "ArrowUp")) {
    event.preventDefault();
    const next = moveCursor(
      state.model.rows,
      state.model.idColumn,
      state.selectedId,
      event.key === "ArrowDown" ? 1 : -1,
    );
    if (next != null && String(next) !== String(state.selectedId)) handlers.select(next);
    return;
  }
  const action = state.model.actions.find((item) => matchKey(event, item.keycode));
  if (action) {
    event.preventDefault();
    handlers.action(action);
    return;
  }
  const relation = (state.model.relations || []).find((item) => matchKey(event, item.keycode));
  if (relation) {
    const target = relationTarget(state.model.card, state.pathname, state.selectedId, relation);
    if (target) {
      event.preventDefault();
      navigate(target, "");
      return;
    }
  }
  if (state.model.kind === "menu") {
    const item = state.model.menu.find((entry) => matchKey(event, entry.keycode));
    if (item) {
      event.preventDefault();
      navigate(item.pathname, "");
    }
    return;
  }
  if (event.key === "Enter" && state.model.kind === "list" && state.selectedId != null) {
    event.preventDefault();
    handlers.open(state.selectedId);
  }
}

async function start() {
  if (accountPath(state.pathname)) {
    window.history.replaceState({}, "", "/");
    state.pathname = "/";
    state.search = "";
  }
  window.addEventListener("popstate", () => {
    state.pathname = window.location.pathname || "/";
    state.search = window.location.search || "";
    loadScreen({ posted: {}, action: null, id: recordId(state.pathname) });
  });
  window.addEventListener("keydown", onKey, true);
  state.session = load();
  if (!state.session) {
    showLogin("");
    return;
  }
  await loadScreen({ posted: {}, action: null, id: recordId(state.pathname) });
}

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.getRegistrations().then((list) => {
    list.forEach((registration) => registration.unregister());
  }).catch(() => {});
}

start();
