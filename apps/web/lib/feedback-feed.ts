import { dictApiBaseUrl } from "./dict-api-base";

export type FeedbackEntry = {
  id: string;
  received_at: string;
  payload: {
    message?: string;
    query?: string;
    mode?: string;
    client_id?: string;
    source_label?: string | null;
    headword?: string | null;
    url?: string | null;
    [key: string]: unknown;
  } | null;
};

type FeedbackEnvelope = {
  request_id: string;
  ok: boolean;
  data: {
    items: FeedbackEntry[];
  } | null;
  error: {
    code: string;
    message: string;
  } | null;
};

export async function loadRecentFeedback(limit = 24): Promise<FeedbackEntry[]> {
  const url = new URL("/feedback/recent", dictApiBaseUrl());
  url.searchParams.set("limit", String(limit));

  try {
    const response = await fetch(url, {
      cache: "no-store",
      headers: {
        Accept: "application/json",
      },
    });

    if (!response.ok) {
      return [];
    }

    const envelope = (await response.json()) as FeedbackEnvelope;
    if (!envelope.ok || !envelope.data?.items) {
      return [];
    }

    return envelope.data.items;
  } catch {
    return [];
  }
}
