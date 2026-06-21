import { dictApiBaseUrl } from "./dict-api-base";

export type SignalsSummary = {
  feedback: {
    total_entries: number;
    with_message_count: number;
    latest_received_at: string | null;
    top_queries: Array<{
      query: string;
      count: number;
    }>;
  };
  activity: {
    history: {
      total_entries: number;
      unique_clients: number;
      top_terms: Array<{
        term: string;
        count: number;
        last_saved_at: number;
      }>;
    };
    inbox: {
      total_entries: number;
      unique_clients: number;
      top_terms: Array<{
        term: string;
        count: number;
        last_saved_at: number;
      }>;
    };
  };
};

type SignalsEnvelope = {
  request_id: string;
  ok: boolean;
  data: SignalsSummary | null;
  error: {
    code: string;
    message: string;
  } | null;
};

export async function loadSignalsSummary(limit = 6): Promise<SignalsSummary | null> {
  const url = new URL("/signals/summary", dictApiBaseUrl());
  url.searchParams.set("limit", String(limit));

  try {
    const response = await fetch(url, {
      cache: "no-store",
      headers: {
        Accept: "application/json",
      },
    });

    if (!response.ok) {
      return null;
    }

    const envelope = (await response.json()) as SignalsEnvelope;
    if (!envelope.ok || !envelope.data) {
      return null;
    }

    return envelope.data;
  } catch {
    return null;
  }
}
