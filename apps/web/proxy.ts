import { NextRequest, NextResponse } from "next/server";

import {
  normalizeClientId,
  sparrowwordClientIdCookieName,
  sparrowwordClientIdHeaderName,
} from "./lib/client-id";

export function proxy(request: NextRequest) {
  const existingClientId = normalizeClientId(
    request.cookies.get(sparrowwordClientIdCookieName)?.value,
  );
  const clientId = existingClientId ?? crypto.randomUUID();

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set(sparrowwordClientIdHeaderName, clientId);

  const response = NextResponse.next({
    request: {
      headers: requestHeaders,
    },
  });

  if (!existingClientId) {
    response.cookies.set({
      name: sparrowwordClientIdCookieName,
      value: clientId,
      httpOnly: true,
      maxAge: 60 * 60 * 24 * 365,
      path: "/",
      sameSite: "lax",
      secure: request.nextUrl.protocol === "https:",
    });
  }

  return response;
}
export const config = {
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico).*)"],
};
