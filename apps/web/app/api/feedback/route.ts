import { NextResponse } from "next/server";

import { readRequestClientId } from "../../../lib/client-session";
import { dictApiBaseUrl } from "../../../lib/dict-api-base";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const payload = await request.json().catch(() => null);
  const clientId = readRequestClientId(request);

  try {
    const response = await fetch(new URL("/feedback", dictApiBaseUrl()), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        ...(payload && typeof payload === "object" ? payload : {}),
        client_id: clientId,
      }),
      cache: "no-store",
    });

    if (!response.ok) {
      return NextResponse.json(
        {
          ok: false,
          error: "feedback_forward_failed",
        },
        {
          status: 502,
        },
      );
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch {
    return NextResponse.json(
      {
        ok: false,
        error: "feedback_unavailable",
      },
      {
        status: 503,
      },
    );
  }
}
