const defaultDictApiBaseUrl = "http://127.0.0.1:3001";

function cleanBaseUrl(value: string | null | undefined): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed || null;
}

export function dictApiBaseUrl(): string {
  const publicBaseUrl = cleanBaseUrl(process.env.NEXT_PUBLIC_SPARROWWORD_DICT_API_BASE_URL);
  if (publicBaseUrl) {
    return publicBaseUrl;
  }

  if (typeof window === "undefined") {
    return cleanBaseUrl(process.env.SPARROWWORD_DICT_API_BASE_URL) ?? defaultDictApiBaseUrl;
  }

  return defaultDictApiBaseUrl;
}
