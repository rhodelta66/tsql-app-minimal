const DEFAULT_AUTH = "https://id3.tsql.app";

export function discover(locationLike) {
  const here = locationLike || window.location;
  const override = typeof window !== "undefined" ? window.TSQL_CLIENT : null;
  if (override && override.api) {
    return {
      api: String(override.api).replace(/\/$/, ""),
      auth: String(override.auth || DEFAULT_AUTH).replace(/\/$/, ""),
    };
  }
  const host = here.hostname || "";
  if (host.startsWith("client.") && host.length > "client.".length) {
    return {
      api: "https://" + host.slice("client.".length),
      auth: DEFAULT_AUTH,
    };
  }
  return {
    api: String(here.origin || "").replace(/\/$/, ""),
    auth: DEFAULT_AUTH,
  };
}

export function accountPath(pathname) {
  return String(pathname || "").toLowerCase().startsWith("/account");
}
