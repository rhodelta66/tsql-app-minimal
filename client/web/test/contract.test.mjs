import assert from "node:assert/strict";
import test from "node:test";
import { accountPath, discover } from "../js/config.js";
import {
  actionsFrom,
  crumbsFrom,
  matchKey,
  modalPosted,
  publicPayload,
  cardBase,
  cursorFor,
  cursorOn,
  moveCursor,
  recordId,
  relationTarget,
  deleteExtra,
  fieldEditor,
  fieldInput,
  fieldWidget,
  optionsFrom,
  formValuesFrom,
  saveExtra,
  screenFrom,
  systemAllowed,
} from "../js/contract.js";
import { errorText, expiring, jwtExp, rolesFromAccess } from "../js/auth.js";

const home = {
  settings: [
    { k: "cardname", v: null },
    { k: "user", v: "ada@example.com" },
    { k: "is_form", v: "0" },
    { k: "is_list", v: "1" },
  ],
  def: [],
  data: [{ id: 1, name: "customer", disp: "customer", keycode: "C" }],
  actions: null,
  breadcrumbs: [],
  error: null,
};

const customer = {
  settings: [
    { k: "cardname", v: "customer" },
    { k: "user", v: "ada@example.com" },
    { k: "id_column", v: "id" },
    { k: "is_form", v: "0" },
    { k: "is_list", v: "1" },
  ],
  def: [
    { name: "id", disp: "ID", is_hid: true },
    { name: "customer_name", disp: "Customer name", is_hid: false },
    { name: "place_label", disp: "Place", is_hid: false, cls: "text-end" },
  ],
  data: [
    { id: 1, customer_name: "Ada Lovegrove", place_label: "Ada Lovegrove - Amsterdam" },
    { id: 3, customer_name: "Chi Ortega", place_label: "Chi Ortega - Utrecht" },
  ],
  actions: [
    { name: "sp_example_minimal_modal", disp: "Note", action: "stored_procedure", keycode: "Alt+N", type: "list_form" },
    { name: "sp_example_wizard", disp: "Wizard", action: "stored_procedure", keycode: "Alt+W", type: "list_form" },
  ],
  breadcrumbs: [{ disp: "customer", card_name: "customer", pathname: "/customer", search: "" }],
};

test("home is a menu even though is_list is 1", () => {
  const screen = screenFrom(home);
  assert.equal(screen.kind, "menu");
  assert.equal(screen.menu[0].pathname, "/customer");
  assert.equal(screen.menu[0].keycode, "C");
  assert.equal(screen.user, "ada@example.com");
  assert.deepEqual(screen.crumbs, [{ label: "Home", pathname: "/", search: "" }]);
});

test("a card list hides fields the server marks hidden", () => {
  const screen = screenFrom(customer);
  assert.equal(screen.kind, "list");
  assert.deepEqual(screen.columns.map((column) => column.name), ["customer_name", "place_label"]);
  assert.equal(screen.columns[1].cls, "text-end");
  assert.equal(screen.actions[0].name, "sp_example_minimal_modal");
  assert.equal(screen.actions[0].label, "Note");
  assert.equal(crumbsFrom(customer)[0].label, "Home");
  assert.equal(crumbsFrom(customer)[1].pathname, "/customer");
});

test("a form follows is_form and still hides detail fields", () => {
  const form = {
    ...customer,
    settings: customer.settings.map((row) => row.k === "is_form" ? { k: "is_form", v: "1" } : row.k === "is_list" ? { k: "is_list", v: "0" } : row),
    def: [
      { name: "id", disp: "ID", is_hid: true },
      { name: "customer_name", disp: "Customer name", is_hid: false },
      { name: "place_label", disp: "Place", is_hid: true },
    ],
    data: [{ id: 1, customer_name: "Ada Lovegrove" }],
    breadcrumbs: [
      { disp: "customer", pathname: "/customer", search: "" },
      { disp: "1", pathname: "/customer/1", search: "" },
    ],
  };
  const screen = screenFrom(form);
  assert.equal(screen.kind, "form");
  assert.deepEqual(screen.columns.map((column) => column.label), ["Customer name"]);
  assert.equal(recordId("/customer/1"), "1");
  assert.equal(recordId("/customer"), null);
});

test("a list cursor points at one record and a form uses the open record", () => {
  const rows = [{ id: 2, name: "Ben" }, { id: 6, name: "Chi" }];
  assert.equal(cursorOn(rows, "id", null), 2);
  assert.equal(cursorOn(rows, "id", 6), 6);
  assert.equal(cursorOn(rows, "id", "6"), 6);
  assert.equal(cursorOn(rows, "id", 99), 2);
  assert.equal(cursorOn([], "id", 2), null);
  assert.equal(moveCursor(rows, "id", 2, 1), 6);
  assert.equal(moveCursor(rows, "id", 6, 1), 6);
  assert.equal(moveCursor(rows, "id", 6, -1), 2);
  assert.equal(moveCursor(rows, "id", null, -1), 2);

  const opened = cursorFor({
    kind: "list",
    base: "/customer",
    cursorBase: "",
    selectedId: 9,
    rows,
    idColumn: "id",
  });
  assert.equal(opened.selectedId, 2);
  assert.equal(opened.cursorBase, "/customer");

  const kept = cursorFor({
    kind: "list",
    base: "/customer",
    cursorBase: "/customer",
    selectedId: 6,
    rows,
    idColumn: "id",
  });
  assert.equal(kept.selectedId, 6);

  const otherCard = cursorFor({
    kind: "list",
    base: "/ide",
    cursorBase: "/customer",
    selectedId: 2,
    rows: [{ id: 7, name: "ide" }],
    idColumn: "id",
  });
  assert.equal(otherCard.selectedId, 7);
  assert.equal(otherCard.cursorBase, "/ide");

  const form = cursorFor({
    kind: "form",
    base: "/customer",
    cursorBase: "/customer",
    selectedId: 6,
    pathId: "2",
    rows: [{ id: 2 }],
    idColumn: "id",
  });
  assert.equal(form.selectedId, "2");

  const creating = cursorFor({
    kind: "form",
    base: "/customer",
    cursorBase: "/customer",
    selectedId: 6,
    pathId: "new",
  });
  assert.equal(creating.selectedId, 6);
  assert.equal(creating.cursorBase, "/customer");

  const child = cursorFor({
    kind: "list",
    base: "/customer/2/customer_note",
    cursorBase: "/customer",
    selectedId: 2,
    rows: [{ id: 3 }, { id: 9 }],
    idColumn: "id",
  });
  assert.equal(child.selectedId, 3);

  const menu = cursorFor({ kind: "menu", base: "", cursorBase: "/customer", selectedId: 6 });
  assert.equal(menu.selectedId, null);
  assert.equal(menu.cursorBase, "");
});

test("a form turns updatable fields into inputs and a save posts them", () => {
  const form = {
    settings: [
      { k: "cardname", v: "customer" },
      { k: "id_column", v: "id" },
      { k: "is_form", v: "1" },
      { k: "is_list", v: "0" },
    ],
    def: [
      { name: "id", disp: "ID", is_hid: 1, is_id: 1, is_upd: 0, typ: "int" },
      { name: "customer_name", disp: "Customer name", is_hid: 0, is_upd: 1, typ: "nvarchar" },
      { name: "credit_limit", disp: "Credit limit", is_hid: 0, is_upd: 1, typ: "decimal" },
      { name: "active", disp: "Active", is_hid: 0, is_upd: 1, typ: "bit" },
      { name: "status", disp: "Status", is_hid: 0, is_upd: 0, typ: "nvarchar" },
      { name: "place_label", disp: "Place", is_hid: 1, is_upd: 0, typ: "" },
    ],
    data: [{ id: 1, customer_name: "Ada", credit_limit: 1200.5, active: true, status: "open" }],
  };
  const screen = screenFrom(form);
  assert.equal(screen.kind, "form");
  const byName = Object.fromEntries(screen.columns.map((column) => [column.name, column]));
  assert.equal(byName.id, undefined);
  assert.equal(byName.place_label, undefined);
  assert.equal(byName.customer_name.editable, true);
  assert.equal(byName.customer_name.input, "text");
  assert.equal(byName.credit_limit.input, "number");
  assert.equal(byName.active.input, "checkbox");
  assert.equal(byName.status.editable, false);
  assert.deepEqual(formValuesFrom(screen), {
    customer_name: "Ada",
    credit_limit: "1200.5",
    active: "1",
  });
  assert.deepEqual(saveExtra("/customer/new", { city: "Leiden" }), {
    save: true,
    delete: false,
    values: { city: "Leiden" },
    posted: {},
    action: null,
    id: null,
  });
  assert.equal(saveExtra("/customer/1", { city: "Leiden" }).id, "1");
  assert.equal(saveExtra("/customer/NEW", {}).id, null);
});

test("a modal heading is a screenplay control, and the modal marker is the dialog", () => {
  const screen = screenFrom({
    modal: {
      class: null,
      controls: [
        { kind: "modal", class: null },
        { kind: "text", text: "hello world", class: "h1" },
      ],
    },
  });
  assert.equal(screen.modal.controls.length, 1);
  assert.equal(screen.modal.controls[0].tag, "h1");
  assert.equal(screen.modal.controls[0].text, "hello world");
  assert.equal(screen.modal.edit, "");
  const linked = screenFrom({
    modal: {
      controls: [{ kind: "text", text: "hello Ada", class: "h1" }],
      edit: "/ide_action/3",
    },
  });
  assert.equal(linked.modal.edit, "/ide_action/3");
  const foreign = screenFrom({
    modal: {
      controls: [{ kind: "text", text: "x", class: "h1" }],
      edit: "https://evil.example/ide_action/3",
    },
  });
  assert.equal(foreign.modal.edit, "");
  const closed = screenFrom({
    cleared: true,
    toasts: [{ text: "Saved successfully", class: "text-success" }],
    modal: { controls: [{ kind: "text", text: "still open", class: "h1" }] },
  });
  assert.equal(closed.modal, null);
  assert.equal(closed.toasts[0].text, "Saved successfully");
});

test("modal posts input names and the clicked button", () => {
  const screen = screenFrom({
    modal: {
      class: "note",
      controls: [
        { kind: "text", text: "Minimal Modal Example", class: "h3" },
        { kind: "input", name: "@my_value", type: "text", value: "kept", placeholder: "Enter a value..." },
        { kind: "button", name: "@btn_save", value: "Save", class: "btn-primary", key: null },
        { kind: "meter", level: 3 },
      ],
    },
  });
  assert.equal(screen.modal.controls[0].tag, "h3");
  assert.equal(screen.modal.controls[3].kind, "unknown");
  const posted = modalPosted(screen.modal.controls, { "@my_value": "" }, screen.modal.controls[2]);
  assert.deepEqual(posted, { "@my_value": "", "@btn_save": "Save" });
});

test("one input procedure covers the form controls", () => {
  assert.equal(fieldWidget("textarea"), "textarea");
  assert.equal(fieldWidget("Select"), "select");
  assert.equal(fieldWidget("datetime-local"), "datetime-local");
  assert.equal(fieldWidget("foo bar"), "text");
  assert.deepEqual(optionsFrom([{ id: "a", name: "Apple" }, "Pear"]), [
    { id: "a", name: "Apple" },
    { id: "Pear", name: "Pear" },
  ]);
  const screen = screenFrom({
    modal: {
      controls: [
        { kind: "input", name: "fruit", type: "select", value: "a", options: [{ id: "a", name: "Apple" }], multiple: true },
        { kind: "input", name: "agree", type: "checkbox", value: null },
        { kind: "input", name: "note", type: "textarea", value: "hi" },
      ],
    },
  });
  assert.equal(screen.modal.controls[0].type, "select");
  assert.equal(screen.modal.controls[0].multiple, true);
  assert.equal(screen.modal.controls[1].value, "0");
  assert.equal(screen.modal.controls[2].type, "textarea");
  const posted = modalPosted(screen.modal.controls, { fruit: "a,b", agree: "1", note: "hi" }, null);
  assert.deepEqual(posted, { fruit: "a,b", agree: "1", note: "hi" });
});

test("an input label is the caption, not a separate control", () => {
  const screen = screenFrom({
    modal: {
      controls: [
        { kind: "text", text: "The input Element", class: "h2" },
        { kind: "input", name: "fname", type: "text", value: "Ada", label: "First name:" },
        { kind: "button", name: "submit", value: "Submit" },
      ],
    },
  });
  assert.equal(screen.modal.controls[0].tag, "h2");
  assert.equal(screen.modal.controls[1].kind, "input");
  assert.equal(screen.modal.controls[1].label, "First name:");
  const posted = modalPosted(screen.modal.controls, { fname: "Ada" }, screen.modal.controls[2]);
  assert.deepEqual(posted, { fname: "Ada", submit: "Submit" });
});

test("shortcuts require the modifiers the server named", () => {
  assert.equal(matchKey({ key: "n", altKey: true, ctrlKey: false, shiftKey: false }, "Alt+N"), true);
  assert.equal(matchKey({ key: "n", altKey: false, ctrlKey: false, shiftKey: false }, "Alt+N"), false);
  assert.equal(matchKey({ key: "c", altKey: false, ctrlKey: false, shiftKey: false, metaKey: true }, "C"), false);
  assert.equal(matchKey({ key: "Enter", altKey: false, ctrlKey: false, shiftKey: false }, "Enter"), true);
});

test("the debug copy drops the session token", () => {
  assert.equal("session" in publicPayload({ session: "secret", data: [] }), false);
});

test("discovery uses the host after client.", () => {
  const found = discover({ hostname: "client.miss-piggy.tsql.app", origin: "https://client.miss-piggy.tsql.app" });
  assert.equal(found.api, "https://miss-piggy.tsql.app");
  assert.equal(found.auth, "https://id3.tsql.app");
  assert.equal(accountPath("/account/login"), true);
  assert.equal(accountPath("/customer"), false);
});

test("sign-in errors and token expiry are readable", () => {
  assert.equal(errorText({ error: { message: "Username and password are required" } }), "Username and password are required");
  const header = Buffer.from(JSON.stringify({ alg: "none" })).toString("base64url");
  const body = Buffer.from(JSON.stringify({ exp: 100 })).toString("base64url");
  assert.equal(jwtExp(header + "." + body + ".sig"), 100);
  assert.equal(expiring({ exp: 100 }, 30), false);
  assert.equal(expiring({ exp: 100 }, 50), true);
});

test("max text is a textarea and a pathname action keeps its path", () => {
  assert.equal(fieldInput("nvarchar(max)"), "textarea");
  assert.equal(fieldInput("varchar(MAX)"), "textarea");
  assert.equal(fieldInput("varbinary(max)"), "textarea");
  assert.equal(fieldInput("nvarchar(128)"), "text");
  assert.equal(fieldInput("nvarchar"), "text");
  const screen = screenFrom({
    settings: [
      { k: "cardname", v: "ide" },
      { k: "id_column", v: "id" },
      { k: "is_form", v: "1" },
      { k: "is_list", v: "0" },
    ],
    def: [
      { name: "reducer", disp: "Reducer", is_hid: 0, is_upd: 1, typ: "nvarchar(max)" },
      { name: "name", disp: "Name", is_hid: 0, is_upd: 1, typ: "nvarchar(128)" },
    ],
    data: [{ id: 1, reducer: "1 = 1", name: "customer" }],
    actions: [{
      name: "fields",
      disp: "Fields",
      action: "pathname",
      type: "list_form",
      params: { pathname: "/ide_field" },
    }],
  });
  const byName = Object.fromEntries(screen.columns.map((column) => [column.name, column]));
  assert.equal(byName.reducer.input, "textarea");
  assert.equal(byName.name.input, "text");
  assert.equal(formValuesFrom(screen).reducer, "1 = 1");
  assert.equal(screen.actions[0].kind, "pathname");
  assert.equal(screen.actions[0].pathname, "/ide_field");
  assert.equal(screen.actions[0].label, "Fields");
  assert.equal(byName.reducer.editor, null);
  assert.equal(screen.canDelete, false);
});

test("button sql uses the editor and delete follows can_delete", () => {
  assert.equal(fieldEditor("sql", "nvarchar(max)"), "sql");
  assert.equal(fieldEditor("SQL", "nvarchar(max)"), "sql");
  assert.equal(fieldEditor("name", "nvarchar(128)"), null);
  assert.equal(fieldEditor("reducer", "nvarchar(max)"), null);
  assert.equal(fieldEditor("params", "nvarchar(max)"), null);
  const screen = screenFrom({
    settings: [
      { k: "cardname", v: "ide_action" },
      { k: "id_column", v: "id" },
      { k: "is_form", v: "1" },
      { k: "is_list", v: "0" },
      { k: "can_delete", v: "1" },
    ],
    def: [
      { name: "sql", disp: "SQL", is_hid: 0, is_upd: 1, typ: "nvarchar(max)" },
      { name: "params", disp: "Params", is_hid: 0, is_upd: 1, typ: "nvarchar(max)" },
      { name: "name", disp: "Name", is_hid: 0, is_upd: 1, typ: "nvarchar(128)" },
    ],
    data: [{ id: 4, sql: "SELECT 1", params: "{}", name: "probe" }],
  });
  const byName = Object.fromEntries(screen.columns.map((column) => [column.name, column]));
  assert.equal(byName.sql.editor, "sql");
  assert.equal(byName.sql.input, "textarea");
  assert.equal(byName.params.editor, null);
  assert.equal(byName.params.input, "textarea");
  assert.equal(byName.name.editor, null);
  assert.equal(screen.canDelete, true);
  assert.equal(formValuesFrom(screen).sql, "SELECT 1");
  assert.equal(deleteExtra("/ide_action/4").delete, true);
  assert.equal(deleteExtra("/ide_action/4").save, false);
  assert.equal(deleteExtra("/ide_action/4").id, "4");
  assert.equal(deleteExtra("/ide_action/4").values, null);
  assert.equal(deleteExtra("/customer/2/customer_note/9").id, "9");
  assert.equal(saveExtra("/ide_action/4", { sql: "SELECT 1" }).delete, false);
  const denied = screenFrom({
    settings: [{ k: "can_delete", v: "0" }, { k: "is_form", v: "1" }],
    def: [{ name: "name", is_hid: 0, is_upd: 1, typ: "nvarchar(128)" }],
    data: [{ name: "customer" }],
  });
  assert.equal(denied.canDelete, false);
});

test("related cards keep the list and build both kinds of path", () => {
  assert.equal(recordId("/customer/1"), "1");
  assert.equal(recordId("/customer/1/customer_note"), null);
  assert.equal(recordId("/customer/1/customer_note/4"), "4");
  assert.equal(recordId("/customer/1/customer_note/new"), "new");
  assert.equal(cardBase("/customer/1"), "/customer");
  assert.equal(cardBase("/customer/1/customer_note"), "/customer/1/customer_note");
  assert.equal(cardBase("/customer/1/customer_note/4"), "/customer/1/customer_note");
  const notes = { name: "customer_note", unbound: false };
  const open = { name: "customer", unbound: true };
  assert.equal(relationTarget("customer", "/customer", "2", notes), "/customer/2/customer_note");
  assert.equal(relationTarget("customer", "/customer", null, notes), null);
  assert.equal(relationTarget("customer", "/customer/2", null, notes), "/customer/2/customer_note");
  assert.equal(relationTarget("customer", "/customer/new", null, notes), null);
  assert.equal(relationTarget("customer", "/customer", null, open), "/customer/-/customer");
  assert.equal(relationTarget("customer", "/customer", "2", open), "/customer/2/customer");
  assert.equal(saveExtra("/customer/2/customer_note/new", {}).id, null);
  assert.equal(saveExtra("/customer/2/customer_note/3", {}).id, "3");
  const screen = screenFrom({
    settings: [
      { k: "cardname", v: "customer" },
      { k: "is_form", v: "0" },
      { k: "is_list", v: "1" },
      { k: "id_column", v: "id" },
    ],
    def: [{ name: "customer_name", disp: "Name", is_hid: 0, typ: "nvarchar(100)" }],
    data: [{ id: 1, name: "Ada", customer_name: "Ada" }],
    relations: [
      { name: "customer_note", disp: "Notes", keycode: null, unbound: false, ref: "customer_id" },
      { name: "customer", disp: "Open customers", unbound: true, ref: null },
      { name: "secret", disp: "Secret", is_hidden: 1, unbound: true },
    ],
  });
  assert.equal(screen.kind, "list");
  assert.equal(screen.menu.length, 0);
  assert.equal(screen.relations.length, 2);
  assert.equal(screen.relations[0].label, "Notes");
  assert.equal(screen.relations[0].unbound, false);
  assert.equal(screen.relations[1].label, "Open customers");
  assert.equal(screen.relations[1].unbound, true);
});

test("a system card verifies the role claim against ide_role", () => {
  const header = btoa(JSON.stringify({ alg: "none", typ: "JWT" })).replace(/=+$/, "");
  const admin = header + "." + btoa(JSON.stringify({ role: "admin" })).replace(/=+$/, "") + ".x";
  const user = header + "." + btoa(JSON.stringify({ role: ["user"] })).replace(/=+$/, "") + ".x";
  const both = header + "." + btoa(JSON.stringify({ role: "admin,user" })).replace(/=+$/, "") + ".x";
  assert.deepEqual(rolesFromAccess(admin), ["admin"]);
  assert.deepEqual(rolesFromAccess(user), ["user"]);
  assert.deepEqual(rolesFromAccess(both), []);
  assert.equal(systemAllowed(0, "admin", []), true);
  assert.equal(systemAllowed(1, "", ["user"]), true);
  assert.equal(systemAllowed(1, "admin", []), false);
  assert.equal(systemAllowed(1, "admin, designer", ["designer"]), true);

  const menu = {
    data: [
      { name: "customer", disp: "customer", keycode: "C", is_system: false },
      { name: "ide", disp: "ide", keycode: "I", is_system: true, ide_role: "admin" },
    ],
  };
  assert.deepEqual(screenFrom(menu, { roles: ["user"] }).menu.map((item) => item.name), ["customer"]);
  assert.deepEqual(screenFrom(menu, { roles: ["admin"] }).menu.map((item) => item.name), ["customer", "ide"]);

  const card = {
    settings: [
      { k: "cardname", v: "ide_action" },
      { k: "is_system", v: "1" },
      { k: "ide_role", v: "admin" },
      { k: "is_form", v: "1" },
    ],
    def: [{ name: "sql", disp: "SQL", is_hid: 0, is_upd: 1, typ: "nvarchar(max)" }],
    data: [{ id: 3, sql: "SELECT @customer_name" }],
    actions: [{ name: "cards", disp: "Cards", action: "pathname" }],
  };
  const hidden = screenFrom(card, { roles: ["user"] });
  assert.equal(hidden.kind, "empty");
  assert.equal(hidden.rows.length, 0);
  assert.equal(hidden.columns.length, 0);
  assert.equal(hidden.actions.length, 0);
  assert.equal(hidden.error, "Code editing requires the role admin.");
  const shown = screenFrom(card, { roles: ["admin"] });
  assert.equal(shown.kind, "form");
  assert.equal(shown.rows[0].sql, "SELECT @customer_name");

  const modal = screenFrom({
    modal: {
      controls: [{ kind: "text", text: "hello", class: "h1" }],
      edit: "/ide_action/3",
      is_system: 1,
      ide_role: "admin",
    },
  }, { roles: ["user"] });
  assert.equal(modal.modal.edit, "");
  const allowed = screenFrom({
    modal: {
      controls: [{ kind: "text", text: "hello", class: "h1" }],
      edit: "/ide_action/3",
      is_system: 1,
      ide_role: "admin",
    },
  }, { roles: ["Admin"] });
  assert.equal(allowed.modal.edit, "/ide_action/3");
});

test("hidden action types stay off the toolbar", () => {
  const actions = actionsFrom({
    actions: [{ name: "secret", disp: "Secret", type: "hidden", action: "stored_procedure" }],
  });
  assert.equal(actions.length, 0);
});
