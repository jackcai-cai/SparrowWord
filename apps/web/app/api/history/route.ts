import { forwardActivityRequest } from "../../../lib/activity-route";

export const dynamic = "force-dynamic";

export function GET(request: Request) {
  return forwardActivityRequest("history", request);
}

export function POST(request: Request) {
  return forwardActivityRequest("history", request);
}

export function DELETE(request: Request) {
  return forwardActivityRequest("history", request);
}
