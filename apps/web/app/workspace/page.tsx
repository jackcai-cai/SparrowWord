import { readServerClientId } from "../../lib/client-session";
import { loadActivityItems, loadWorkspacePersistenceState, loadWorkspaceState } from "../../lib/dict-api";
import { inferLookupKind } from "../../lib/mock-workspace";
import { starterQueries } from "../../lib/mock-workspace";
import WorkspaceClient from "./workspace-client";

type WorkspacePageProps = {
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
};

export const dynamic = "force-dynamic";

function readSection(value: string | null): "lookup" | "library" | "review" | "history" {
  if (
    value === "lookup" ||
    value === "library" ||
    value === "review" ||
    value === "history"
  ) {
    return value;
  }

  return "lookup";
}

function readParam(value: string | string[] | undefined): string | null {
  if (Array.isArray(value)) {
    return value[0] ?? null;
  }

  return value ?? null;
}

export default async function WorkspacePage({ searchParams }: WorkspacePageProps) {
  const params = (await searchParams) ?? {};
  const clientId = await readServerClientId();
  const initialSection = readSection(readParam(params.section));
  const rawQuery = readParam(params.q);
  const rawKind = readParam(params.kind);
  const initialSelectedActivityId = readParam(params.item);
  const initialSelectedLibraryEntryId = readParam(params.entry);
  const initialContext = readParam(params.context) ?? "";
  const initialSource = readParam(params.source);
  const [initialHistoryItems, initialInboxItems, initialPersistedState] = await Promise.all([
    loadActivityItems("history", clientId),
    loadActivityItems("inbox", clientId),
    loadWorkspacePersistenceState(clientId),
  ]);
  const fallbackQuery =
    rawQuery?.trim() ||
    (initialSection === "history" ? initialHistoryItems[0]?.term : "") ||
    "";
  const initialKind = inferLookupKind(rawKind, fallbackQuery);
  const workspace = await loadWorkspaceState(
    fallbackQuery,
    initialSource ?? (initialSection === "lookup" ? null : initialSection),
    initialKind,
  );

  return (
    <WorkspaceClient
      initialClientId={clientId}
      initialHistoryItems={initialHistoryItems}
      initialInboxItems={initialInboxItems}
      initialKind={initialKind}
      initialPersistedState={initialPersistedState}
      initialContext={initialContext}
      initialSelectedActivityId={initialSelectedActivityId}
      initialSelectedLibraryEntryId={initialSelectedLibraryEntryId}
      initialSection={initialSection}
      initialSource={initialSource}
      initialWorkspace={workspace}
      starterQueries={starterQueries}
    />
  );
}
