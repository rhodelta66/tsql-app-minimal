export function requestUrl(apiBase) {
  return String(apiBase || "").replace(/\/$/, "") + "/api/request";
}

export async function screen(apiBase, token, body) {
  const response = await fetch(requestUrl(apiBase), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer " + token,
    },
    body: JSON.stringify({
      pathname: body.pathname || "/",
      posted: body.posted || {},
      action: body.action || null,
      id: body.id == null || body.id === "" ? null : String(body.id),
      ids: body.ids == null || body.ids === "" ? null : String(body.ids),
      close: Boolean(body.close),
      save: Boolean(body.save),
      delete: Boolean(body.delete),
      values: body.values && typeof body.values === "object" && !Array.isArray(body.values) ? body.values : null,
    }),
    cache: "no-store",
    credentials: "omit",
  });
  const text = await response.text();
  let payload = null;
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch {
      payload = null;
    }
  }
  if (response.status === 401) {
    const error = new Error("Unauthorized");
    error.status = 401;
    throw error;
  }
  if (!response.ok || !payload || typeof payload !== "object" || Array.isArray(payload)) {
    const error = new Error((payload && payload.error) || "Unexpected server response (HTTP " + response.status + ")");
    error.status = response.status;
    throw error;
  }
  return payload;
}
