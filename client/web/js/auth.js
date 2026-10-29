const KEY = "tsql.auth";

export function errorText(body) {
  if (!body) return "Sign-in failed";
  if (typeof body === "string") return body;
  if (typeof body.error === "string") return body.error;
  if (body.error && typeof body.error.message === "string") return body.error.message;
  return "Sign-in failed";
}

export function jwtExp(token) {
  try {
    const part = String(token).split(".")[1];
    if (!part) return 0;
    const padded = part.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((part.length + 3) % 4);
    const claims = JSON.parse(atob(padded));
    const exp = Number(claims.exp || 0);
    return Number.isFinite(exp) ? exp : 0;
  } catch {
    return 0;
  }
}

const ROLE_NAME = /^[A-Za-z0-9_. -]{1,128}$/;

export function rolesFromAccess(token) {
  let claims = {};
  try {
    const part = String(token || "").split(".")[1];
    if (part) {
      const padded = part.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((part.length + 3) % 4);
      const parsed = JSON.parse(atob(padded));
      if (parsed && typeof parsed === "object") claims = parsed;
    }
  } catch {
    claims = {};
  }
  const raw = claims.role;
  const items = typeof raw === "string" ? [raw] : Array.isArray(raw) ? raw.filter((item) => typeof item === "string") : [];
  const found = [];
  const seen = new Set();
  for (const item of items) {
    const name = item.trim();
    if (!ROLE_NAME.test(name)) continue;
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    found.push(name);
    if (found.length === 32) break;
  }
  return found;
}

export function claimName(token) {
  try {
    const part = String(token).split(".")[1];
    if (!part) return "";
    const padded = part.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((part.length + 3) % 4);
    const claims = JSON.parse(atob(padded));
    return String(claims.email || claims.preferred_username || claims.sub || "");
  } catch {
    return "";
  }
}

function pack(body) {
  if (!body || typeof body !== "object" || !body.uid) return null;
  const access = body.access_token || body.idToken || "";
  if (!access || access.split(".").length !== 3) return null;
  const skew = Number(body.expires_in || body.accessTokenExpirationSeconds || 0);
  const exp = skew > 0 ? Math.floor(Date.now() / 1000) + skew - 30 : jwtExp(access);
  return {
    access,
    refresh: body.refresh_token || body.refreshToken || "",
    uid: String(body.uid),
    exp,
  };
}

export function load() {
  try {
    const raw = sessionStorage.getItem(KEY);
    if (!raw) return null;
    const saved = JSON.parse(raw);
    if (!saved || !saved.access || String(saved.access).split(".").length !== 3) return null;
    return saved;
  } catch {
    return null;
  }
}

export function save(session) {
  sessionStorage.setItem(KEY, JSON.stringify(session));
}

export function clear() {
  try {
    sessionStorage.removeItem(KEY);
  } catch {
    /* storage can be blocked */
  }
}

export function expiring(session, nowSeconds) {
  if (!session || !session.exp) return false;
  const now = nowSeconds == null ? Math.floor(Date.now() / 1000) : nowSeconds;
  return session.exp - now < 60;
}

async function postJson(url, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    cache: "no-store",
    credentials: "omit",
  });
  const text = await response.text();
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch {
    return { error: { message: "Unexpected sign-in response" } };
  }
}

export async function login(authBase, username, password) {
  const body = await postJson(authBase.replace(/\/$/, "") + "/login", { username, password });
  if (body && body.needs_2fa) return { needs2fa: true };
  if (body && body.error) return { error: errorText(body) };
  const session = pack(body);
  if (!session) return { error: "The identity server did not return a bearer token." };
  save(session);
  return { session };
}

export async function verify(authBase, username, code) {
  const body = await postJson(authBase.replace(/\/$/, "") + "/login/verify", { username, code });
  if (body && body.error) return { error: errorText(body) };
  const session = pack(body);
  if (!session) return { error: "The identity server did not return a bearer token." };
  save(session);
  return { session };
}

export async function refresh(authBase, session) {
  if (!session || !session.refresh || !session.uid) return null;
  const body = await postJson(authBase.replace(/\/$/, "") + "/refresh", {
    uid: session.uid,
    token: session.refresh,
  });
  const next = pack(body);
  if (!next) return null;
  save(next);
  return next;
}
