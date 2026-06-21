import { NextResponse } from "next/server";

import { readRequestClientId } from "./client-session";
import { dictApiBaseUrl } from "./dict-api-base";

type ActivityKind = "history" | "inbox";

function proxyError(code: string, message: string, status: number) {
  return NextResponse.json(
    {
      ok: false,
      error: {
        code,
        message,
      },
    },
    {
      status,
    },
  );
}

export async function forwardActivityRequest(
  kind: ActivityKind,
  request: Request,
) {
  const clientId = readRequestClientId(request);
  if (!clientId) {
    return proxyError("missing_client_id", "Anonymous client id is required.", 400);
  }

  const url = new URL(`/${kind}`, dictApiBaseUrl());
  const init: RequestInit = {
    cache: "no-store",
    headers: {
      Accept: "application/json",
    },
    method: request.method,
  };

  if (request.method === "GET") {
    url.searchParams.set("client_id", clientId);
  } else {
    const payload = await request.json().catch(() => ({}));
    init.headers = {
      ...init.headers,
      "Content-Type": "application/json",
    };
    init.body = JSON.stringify({
      ...(payload && typeof payload === "object" ? payload : {}),
      client_id: clientId,
    });
  }

  try {
    const response = await fetch(url, init);
    const data = await response.json().catch(() => null);

    if (!response.ok) {
      return NextResponse.json(
        data ?? {
          ok: false,
          error: {
            code: `${kind}_forward_failed`,
            message: `Unable to forward ${kind} request.`,
          },
        },
        {
          status: response.status,
        },
      );
    }

    return NextResponse.json(data);
  } catch {
    return proxyError(`${kind}_unavailable`, `Unable to reach ${kind} service.`, 503);
  }
}
