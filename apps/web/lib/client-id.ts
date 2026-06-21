export const sparrowwordClientIdCookieName = "sparrowword_client_id";
export const sparrowwordClientIdHeaderName = "x-sparrowword-client-id";

export function normalizeClientId(value: string | null | undefined): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const normalized = value.trim();
  if (!normalized || normalized.length > 128) {
    return null;
  }

  return normalized;
}
