import { NextResponse } from "next/server";

import { dictApiBaseUrl } from "../../../lib/dict-api-base";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const query = url.searchParams.get("q")?.trim() ?? "";

  if (!query) {
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: "missing_query",
          message: "A non-empty q parameter is required.",
        },
      },
      { status: 400 },
    );
  }

  const lookupUrl = new URL("/lookup", dictApiBaseUrl());
  lookupUrl.searchParams.set("q", query);

  try {
    const response = await fetch(lookupUrl, {
      cache: "no-store",
      headers: {
        Accept: "application/json",
      },
    });
    const data = await response.json().catch(() => null);

    if (!response.ok) {
      return NextResponse.json(
        data ?? {
          ok: false,
          error: {
            code: "lookup_forward_failed",
            message: "Unable to fetch lookup data.",
          },
        },
        { status: response.status },
      );
    }

    return NextResponse.json(data);
  } catch {
    return NextResponse.json(
      {
        ok: false,
        error: {
          code: "lookup_unavailable",
          message: "Unable to reach the lookup service.",
        },
      },
      { status: 503 },
    );
  }
}
