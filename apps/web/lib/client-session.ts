import { cookies, headers } from "next/headers";

import {
  normalizeClientId,
  sparrowwordClientIdCookieName,
  sparrowwordClientIdHeaderName,
} from "./client-id";

export async function readServerClientId(): Promise<string | null> {
  const headerStore = await headers();
  const headerValue = normalizeClientId(
    headerStore.get(sparrowwordClientIdHeaderName),
  );
  if (headerValue) {
    return headerValue;
  }

  const cookieStore = await cookies();
  return normalizeClientId(cookieStore.get(sparrowwordClientIdCookieName)?.value);
}

function readClientIdFromCookieHeader(cookieHeader: string | null): string | null {
  if (!cookieHeader) {
    return null;
  }

  const pairs = cookieHeader.split(";");
  for (const pair of pairs) {
    const [rawName, ...rest] = pair.split("=");
    if (!rawName || rest.length === 0) {
      continue;
    }

    if (rawName.trim() !== sparrowwordClientIdCookieName) {
      continue;
    }

    return normalizeClientId(rest.join("=").trim());
  }

  return null;
}

export function readRequestClientId(request: Request): string | null {
  const headerValue = normalizeClientId(request.headers.get(sparrowwordClientIdHeaderName));
  if (headerValue) {
    return headerValue;
  }

  return readClientIdFromCookieHeader(request.headers.get("cookie"));
}
