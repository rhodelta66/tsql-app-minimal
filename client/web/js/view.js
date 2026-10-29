// Paint a screen model. Text from the server is assigned with textContent.

import { recordId, relationTarget } from "./contract.js";
import { disposeSqlEditors, mountSqlEditor } from "./editor.js";

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

function button(label, className, onClick) {
  const node = el("button", className, label);
  node.type = "button";
  node.addEventListener("click", onClick);
  return node;
}

function crumbNav(model, handlers) {
  const nav = el("nav", "crumbs");
  nav.setAttribute("aria-label", "Breadcrumb");
  model.crumbs.forEach((crumb, index) => {
    if (index) nav.append(el("span", "sep", "/"));
    const last = index === model.crumbs.length - 1;
    const node = button(crumb.label, last ? "crumb current" : "crumb", () => {
      if (!last) handlers.navigate(crumb.pathname, crumb.search || "");
    });
    if (last) node.disabled = true;
    nav.append(node);
  });
  return nav;
}

function relatedMenu(model, handlers) {
  const details = el("details", "related");
  details.append(el("summary", "related-button", "Related"));
  const menu = el("div", "related-menu");
  menu.setAttribute("role", "menu");
  for (const relation of model.relations) {
    const target = relationTarget(model.card, handlers.pathname, handlers.selectedId, relation);
    const node = button(relation.label, "related-item", () => {
      if (target) handlers.relation(relation);
    });
    node.setAttribute("role", "menuitem");
    node.disabled = target == null;
    node.append(el("span", "related-kind", relation.unbound ? "unbound" : "bound"));
    menu.append(node);
  }
  details.append(menu);
  return details;
}

function toolbar(model, handlers) {
  const bar = el("div", "toolbar");
  if (model.kind === "list" && model.card) {
    bar.append(button("New", "action", () => handlers.openNew()));
  }
  for (const action of model.actions) {
    const node = button(action.label, "action", () => handlers.action(action));
    if (action.keycode) {
      const hint = el("kbd", null, action.keycode);
      node.append(hint);
    }
    bar.append(node);
  }
  if ((model.kind === "list" || model.kind === "form") && model.relations.length) {
    bar.append(relatedMenu(model, handlers));
  }
  return bar;
}

function menu(model, handlers) {
  const wrap = el("div", "menu");
  if (!model.menu.length) {
    wrap.append(el("p", "empty", "No cards in the menu."));
    return wrap;
  }
  for (const item of model.menu) {
    const node = button(item.label, "menu-card", () => handlers.navigate(item.pathname, ""));
    if (item.keycode) node.append(el("kbd", null, item.keycode));
    wrap.append(node);
  }
  return wrap;
}

function list(model, handlers) {
  const wrap = el("div", "grid-wrap");
  const table = el("table", "grid");
  const head = el("tr");
  for (const column of model.columns) {
    head.append(el("th", column.cls, column.label));
  }
  const thead = el("thead");
  thead.append(head);
  const body = el("tbody");
  if (!model.rows.length) {
    const row = el("tr");
    const cell = el("td", "empty", "No rows.");
    cell.colSpan = Math.max(model.columns.length, 1);
    row.append(cell);
    body.append(row);
  }
  for (const record of model.rows) {
    const id = record[model.idColumn];
    const selected = id != null && String(id) === String(handlers.selectedId);
    const row = el("tr", selected ? "selected" : "");
    row.setAttribute("aria-selected", selected ? "true" : "false");
    if (id != null && String(id) !== "") row.dataset.id = String(id);
    row.tabIndex = selected ? 0 : -1;
    row.addEventListener("click", () => handlers.select(id));
    row.addEventListener("dblclick", () => handlers.open(id));
    for (const column of model.columns) {
      const raw = record[column.name];
      row.append(el("td", column.cls, raw == null ? "" : String(raw)));
    }
    body.append(row);
  }
  table.append(thead, body);
  wrap.append(table);
  return wrap;
}

function form(model, handlers) {
  const grid = el("form", "form");
  grid.addEventListener("submit", (event) => {
    event.preventDefault();
    handlers.save();
  });
  const record = model.rows[0];
  if (!record) {
    grid.append(el("p", "empty", "No record."));
    return grid;
  }
  const typed = handlers.formValues || {};
  let editable = false;
  for (const column of model.columns) {
    const label = el("label", "label", column.label);
    const fieldId = "field-" + column.name;
    label.htmlFor = fieldId;
    grid.append(label);
    if (column.editable) {
      editable = true;
      const current = Object.prototype.hasOwnProperty.call(typed, column.name)
        ? typed[column.name]
        : record[column.name];
      let input;
      if (column.editor === "sql") {
        label.classList.add("sql-label");
        const host = document.createElement("div");
        host.id = fieldId;
        host.className = ("sql-editor " + column.cls).trim();
        grid.append(host);
        mountSqlEditor(host, current == null ? "" : String(current), {
          input(text) {
            handlers.formInput(column.name, text);
          },
          save() {
            handlers.save();
          },
        });
        continue;
      }
      if (column.input === "textarea") {
        input = document.createElement("textarea");
        input.value = current == null ? "" : String(current);
        input.addEventListener("input", () => handlers.formInput(column.name, input.value));
      } else {
        input = document.createElement("input");
        input.autocomplete = "off";
        if (column.input === "checkbox") {
          input.type = "checkbox";
          input.checked = current === "1" || current === 1 || current === true;
          input.addEventListener("change", () => handlers.formInput(column.name, input.checked ? "1" : "0"));
        } else {
          input.type = column.input || "text";
          if (input.type === "number") input.step = "any";
          input.value = current == null ? "" : String(current);
          input.addEventListener("input", () => handlers.formInput(column.name, input.value));
        }
      }
      input.id = fieldId;
      input.name = column.name;
      input.className = column.cls;
      grid.append(input);
    } else {
      const raw = record[column.name];
      const value = el("div", "value " + column.cls, raw == null ? "" : String(raw));
      value.id = fieldId;
      grid.append(value);
    }
  }
  const creating = /^new$/i.test(String(recordId(handlers.pathname) || ""));
  const showDelete = model.canDelete && !creating;
  if (editable || showDelete) {
    const row = el("div", "save-row");
    if (showDelete) row.append(button("Delete", "action danger", () => handlers.remove()));
    if (editable) {
      const save = el("button", "action", "Save");
      save.type = "submit";
      save.append(el("kbd", null, "Ctrl+S"));
      row.append(save);
    }
    grid.append(row);
  }
  return grid;
}

function chosenSet(value) {
  return new Set(String(value || "").split(",").map((part) => part.trim()).filter(Boolean));
}

function appendModalField(body, control, handlers) {
  const widget = control.type || "text";
  if (widget === "hidden") {
    const input = document.createElement("input");
    input.type = "hidden";
    input.name = control.name;
    if (control.name) input.id = control.name;
    input.value = control.value;
    body.append(input);
    return;
  }
  if (widget === "radio" || (widget === "checkbox" && control.options.length)) {
    const group = el("fieldset");
    if (control.label) group.append(el("legend", null, control.label));
    for (const option of control.options) {
      const item = el("label", "choice");
      const input = document.createElement("input");
      input.type = widget === "radio" ? "radio" : "checkbox";
      input.name = control.name;
      input.value = option.id;
      const chosen = chosenSet(control.value);
      input.checked = widget === "radio" ? control.value === option.id : chosen.has(option.id);
      input.addEventListener("change", () => {
        if (widget === "radio") {
          handlers.modalInput(control.name, option.id);
          return;
        }
        const values = [];
        group.querySelectorAll('input[type="checkbox"]').forEach((box) => {
          if (box.checked) values.push(box.value);
        });
        handlers.modalInput(control.name, values.join(","));
      });
      item.append(input, document.createTextNode(option.name));
      group.append(item);
    }
    body.append(group);
    return;
  }
  if (widget === "checkbox") {
    const label = el("label", "choice");
    const input = document.createElement("input");
    input.type = "checkbox";
    input.name = control.name;
    if (control.name) {
      input.id = control.name;
      label.htmlFor = control.name;
    }
    input.checked = control.value === "1";
    input.addEventListener("change", () => handlers.modalInput(control.name, input.checked ? "1" : "0"));
    label.append(input);
    if (control.label) label.append(document.createTextNode(control.label));
    body.append(label);
    return;
  }
  const label = el("label");
  if (control.name) label.htmlFor = control.name;
  if (control.label) label.append(document.createTextNode(control.label));
  let input;
  if (widget === "textarea") {
    input = document.createElement("textarea");
    input.value = control.value;
    if (control.placeholder) input.placeholder = control.placeholder;
    input.addEventListener("input", () => handlers.modalInput(control.name, input.value));
  } else if (widget === "select") {
    input = document.createElement("select");
    if (control.multiple) input.multiple = true;
    if (!control.multiple) {
      const blank = document.createElement("option");
      blank.value = "";
      blank.textContent = control.placeholder || "";
      input.append(blank);
    }
    for (const option of control.options) {
      const item = document.createElement("option");
      item.value = option.id;
      item.textContent = option.name;
      input.append(item);
    }
    if (control.multiple) {
      const chosen = chosenSet(control.value);
      for (const item of input.options) item.selected = chosen.has(item.value);
    } else {
      input.value = control.value;
    }
    input.addEventListener("change", () => {
      if (!control.multiple) {
        handlers.modalInput(control.name, input.value || "");
        return;
      }
      const values = [];
      for (const item of input.selectedOptions) {
        if (item.value) values.push(item.value);
      }
      handlers.modalInput(control.name, values.join(","));
    });
  } else if (widget === "file") {
    input = document.createElement("input");
    input.type = "file";
    input.addEventListener("change", () => {
      const file = input.files && input.files[0];
      if (!file) {
        handlers.modalInput(control.name, "");
        return;
      }
      const reader = new FileReader();
      reader.onload = () => handlers.modalInput(control.name, String(reader.result || ""));
      reader.readAsDataURL(file);
    });
  } else {
    input = document.createElement("input");
    input.type = widget;
    if (widget === "number" || widget === "range") input.step = "any";
    input.value = control.value;
    if (control.placeholder) input.placeholder = control.placeholder;
    input.addEventListener("input", () => handlers.modalInput(control.name, input.value));
  }
  input.name = control.name;
  if (control.name) input.id = control.name;
  if (control.focus) input.dataset.focus = "1";
  label.append(input);
  body.append(label);
}

function modal(model, handlers) {
  const dialog = el("dialog", "modal " + (model.modal.className || ""));
  dialog.addEventListener("cancel", (event) => {
    event.preventDefault();
    handlers.escape();
  });
  const card = el("form", "modal-card");
  card.addEventListener("submit", (event) => {
    event.preventDefault();
    const buttons = model.modal.controls.filter((control) => control.kind === "button");
    const enter = buttons.find((control) => /^enter$/i.test(control.key)) || (buttons.length === 1 ? buttons[0] : null);
    if (enter) handlers.modalButton(enter);
  });
  const head = el("div", "modal-head");
  head.append(el("p", "eyebrow", "Dialog"));
  if (model.modal.edit) {
    head.append(button("Edit", "text-button", () => handlers.navigate(model.modal.edit, "")));
  }
  head.append(button("Close", "text-button", () => handlers.close()));
  card.append(head);
  const body = el("div", "modal-body");
  const actions = el("div", "modal-actions");
  for (const control of model.modal.controls) {
    if (control.kind === "text") {
      body.append(el(control.tag, control.className, control.text));
    } else if (control.kind === "input") {
      appendModalField(body, control, handlers);
    } else if (control.kind === "button") {
      const node = button(control.value || control.name, "action " + control.className, () => handlers.modalButton(control));
      if (control.key) node.append(el("kbd", null, control.key));
      actions.append(node);
    } else {
      const note = el("p", "unknown", "Unsupported control");
      note.append(el("code", null, control.text || control.kind));
      body.append(note);
    }
  }
  card.append(body, actions);
  dialog.append(card);
  return dialog;
}

function toasts(model) {
  const wrap = el("div", "toasts");
  wrap.setAttribute("aria-live", "polite");
  for (const toast of model.toasts) {
    if (!toast.text) continue;
    wrap.append(el("div", "toast " + toast.className, toast.text));
  }
  return wrap;
}

export function paint(root, state, handlers) {
  disposeSqlEditors();
  root.replaceChildren();
  if (state.mode === "login") {
    root.append(login(state, handlers));
    const field = root.querySelector(state.needs2fa ? "input[name=code]" : "input[name=username]");
    if (field) field.focus();
    return;
  }
  const model = state.model;
  const shell = el("div", "shell" + (state.busy ? " busy" : ""));
  const header = el("header");
  header.append(el("p", "brand", "tsql"));
  const titles = el("div");
  titles.append(el("p", "eyebrow", model.kind));
  titles.append(el("h1", null, model.title));
  header.append(titles);
  const who = el("div", "who");
  who.append(el("span", null, state.who || model.user || ""));
  who.append(button("Log out", "text-button", () => handlers.logout()));
  header.append(who);
  shell.append(header);
  shell.append(crumbNav(model, handlers));
  shell.append(toolbar(model, handlers));
  const message = state.error || model.error;
  if (message) {
    const banner = el("p", "banner", message);
    banner.setAttribute("role", "alert");
    shell.append(banner);
  }
  const main = el("main");
  if (!state.payload) main.append(el("p", "empty", "Loading…"));
  else if (model.kind === "menu") main.append(menu(model, handlers));
  else if (model.kind === "form") main.append(form(model, handlers));
  else if (model.kind === "list") main.append(list(model, handlers));
  else main.append(el("p", "empty", "Nothing to show."));
  shell.append(main);
  shell.append(toasts(model));
  const details = el("details", "payload");
  details.append(el("summary", null, "Payload"));
  details.append(el("pre", null, state.payloadText || ""));
  shell.append(details);
  root.append(shell);
  if (model.modal) {
    const dialog = modal(model, handlers);
    root.append(dialog);
    if (!dialog.open) dialog.showModal();
    const focus = dialog.querySelector("[data-focus='1'], input");
    if (focus) focus.focus();
  } else if (model.kind === "form") {
    const first = root.querySelector(".form input, .form textarea");
    if (first) first.focus();
  } else if (model.kind === "list") {
    const current = root.querySelector("tr.selected");
    if (current) {
      current.scrollIntoView({ block: "nearest" });
      const active = document.activeElement;
      const editable = active && (/^(INPUT|TEXTAREA|SELECT)$/.test(active.tagName) || active.isContentEditable);
      const lost = !active || active === document.body || active === document.documentElement || !root.contains(active);
      const inGrid = !!(active && active.closest && active.closest(".grid-wrap"));
      if (!editable && (lost || inGrid)) current.focus({ preventScroll: true });
    }
  }
  document.title = model.title + " · tsql";
}

function login(state, handlers) {
  const main = el("main", "gate");
  const formNode = el("form", "gate-card");
  formNode.addEventListener("submit", (event) => {
    event.preventDefault();
    const data = new FormData(formNode);
    if (state.needs2fa) handlers.verify(String(data.get("code") || ""));
    else handlers.login(String(data.get("username") || ""), String(data.get("password") || ""));
  });
  formNode.append(el("p", "brand", "tsql"));
  formNode.append(el("h1", null, state.needs2fa ? "Check code" : "Sign in"));
  formNode.append(el("p", "lede", state.needs2fa
    ? "Enter the code for " + (state.username || "this account") + "."
    : "The screen after this is whatever the server sends."));
  if (state.needs2fa) {
    const label = el("label", null, "Code");
    const input = document.createElement("input");
    input.name = "code";
    input.autocomplete = "one-time-code";
    input.inputMode = "numeric";
    label.append(input);
    formNode.append(label);
  } else {
    const user = el("label", null, "Email");
    const userInput = document.createElement("input");
    userInput.name = "username";
    userInput.type = "email";
    userInput.autocomplete = "username";
    userInput.required = true;
    userInput.value = state.username || "";
    user.append(userInput);
    const pass = el("label", null, "Password");
    const passInput = document.createElement("input");
    passInput.name = "password";
    passInput.type = "password";
    passInput.autocomplete = "current-password";
    passInput.required = true;
    pass.append(passInput);
    formNode.append(user, pass);
  }
  if (state.error) {
    const banner = el("p", "banner", state.error);
    banner.setAttribute("role", "alert");
    formNode.append(banner);
  }
  const submit = el("button", "action", state.needs2fa ? "Verify" : "Sign in");
  submit.type = "submit";
  formNode.append(submit);
  main.append(formNode);
  return main;
}
