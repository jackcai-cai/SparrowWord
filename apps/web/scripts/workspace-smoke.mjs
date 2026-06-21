const baseUrl = process.env.SPARROWWORD_WEB_BASE_URL?.trim() || "http://localhost:3000";
const dictApiBaseUrl =
  process.env.SPARROWWORD_DICT_API_BASE_URL?.trim() ||
  process.env.NEXT_PUBLIC_SPARROWWORD_DICT_API_BASE_URL?.trim() ||
  "http://127.0.0.1:3001";
const clientIdHeaderName = "x-sparrowword-client-id";

const checks = [
  {
    label: "review route",
    path: "/workspace?section=review",
    expect: ["Review", "Sources", "Question types"],
  },
  {
    label: "library route",
    path: "/workspace?section=library",
    expect: ["Library"],
  },
  {
    label: "sentence workspace route",
    path: "/workspace?section=lookup&kind=sentence&q=The%20committee%20is%20clamping%20down%20on%20wasteful%20spending.",
    expect: ["Lookup", "Sentence"],
  },
  {
    label: "Chinese reverse lookup route",
    path: "/workspace?section=lookup&kind=word&q=%E5%BD%BB%E5%BA%95&source=search",
    expect: ["Chinese query", "English candidates", "complete", "thorough"],
  },
];

function absoluteUrl(root, path) {
  return new URL(path, root).toString();
}

async function readTextResponse(url, init, label) {
  const response = await fetch(url, {
    ...init,
    headers: {
      Accept: "text/html",
      ...init?.headers,
    },
  });

  if (!response.ok) {
    throw new Error(`${label} returned ${response.status}`);
  }

  return response.text();
}

async function runCheck(check, headers = {}) {
  const html = await readTextResponse(
    absoluteUrl(baseUrl, check.path),
    { headers },
    check.label,
  );
  for (const expected of check.expect) {
    if (!html.includes(expected)) {
      throw new Error(`${check.label} did not include expected text: ${expected}`);
    }
  }

  console.log(`ok - ${check.label}`);
}

async function readJsonResponse(url, init, label) {
  const response = await fetch(url, {
    ...init,
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      ...init?.headers,
    },
  });

  const data = await response.json().catch(() => null);
  if (!response.ok) {
    const message = data?.error?.message ? `: ${data.error.message}` : "";
    throw new Error(`${label} returned ${response.status}${message}`);
  }

  return data;
}

async function clearActivity(kind, clientId) {
  await readJsonResponse(
    absoluteUrl(baseUrl, `/api/${kind}`),
    {
      method: "DELETE",
      headers: {
        [clientIdHeaderName]: clientId,
      },
      body: JSON.stringify({}),
    },
    `clear ${kind}`,
  );
}

async function upsertActivity(kind, clientId, item) {
  await readJsonResponse(
    absoluteUrl(baseUrl, `/api/${kind}`),
    {
      method: "POST",
      headers: {
        [clientIdHeaderName]: clientId,
      },
      body: JSON.stringify(item),
    },
    `upsert ${kind}`,
  );
}

async function writeWorkspaceState(clientId, snapshot) {
  await readJsonResponse(
    absoluteUrl(dictApiBaseUrl, "/workspace-state"),
    {
      method: "PUT",
      body: JSON.stringify({
        client_id: clientId,
        snapshot,
      }),
    },
    "write workspace state",
  );
}

async function runWorkspaceChainCheck() {
  const now = Date.now();
  const clientId = `workspace-smoke-${now}`;
  const pageHeaders = {
    Cookie: `sparrowword_client_id=${clientId}`,
  };
  const term = "abandon";
  const detail = "放弃";
  const context = "They had to abandon the original plan.";
  const savedAt = now - 1000;
  const activityItem = {
    term,
    detail,
    context,
    saved_at: savedAt,
  };

  await clearActivity("history", clientId);
  await clearActivity("inbox", clientId);
  await writeWorkspaceState(clientId, {
    libraryEntries: [],
    savedLibraryArrangements: [],
    inboxEntryDrafts: {},
    reviewStateMap: {},
    reviewHistory: [],
    reviewSession: null,
    workspacePreferences: {},
    trashItems: [],
  });

  await runCheck(
    {
      label: "chain lookup route",
      path: "/workspace?section=lookup&kind=word&q=abandon&source=smoke",
      expect: ["Lookup", "abandon", "Save to Inbox", "Confirm into Library"],
    },
    pageHeaders,
  );

  await upsertActivity("history", clientId, {
    ...activityItem,
    meta: {
      originalQuery: term,
      sourceLabel: "Lookup",
      lookupKind: "word",
      lookupMode: "lookup",
      inboxAction: "createdInbox",
      status: "completed",
      statusMessage: "Showing abandon.",
    },
  });
  await upsertActivity("inbox", clientId, activityItem);

  await runCheck(
    {
      label: "chain inbox route",
      path: "/workspace?section=inbox&kind=word&q=abandon",
      expect: ["Inbox", "abandon", detail, "Confirm into Library"],
    },
    pageHeaders,
  );

  await clearActivity("inbox", clientId);
  await writeWorkspaceState(clientId, {
    libraryEntries: [
      {
        id: `library-${term}-${now}`,
        kind: "word",
        term,
        partOfSpeech: "verb",
        detail,
        meaningChoices: [detail],
        meaningChoicePartOfSpeechLabels: ["verb"],
        selectedMeaningIndexes: [0],
        exampleChoices: [context],
        selectedExampleIndexes: [0],
        englishDefinitions: ["forsake, leave behind"],
        inflectionLines: ["Past: abandoned"],
        referenceTags: ["ECDICT"],
        notes: "",
        context,
        favorite: false,
        savedAt,
        updatedAt: now,
      },
    ],
    savedLibraryArrangements: [],
    inboxEntryDrafts: {},
    reviewStateMap: {},
    reviewHistory: [],
    reviewSession: null,
    workspacePreferences: {},
    trashItems: [],
  });

  await runCheck(
    {
      label: "chain library route",
      path: "/workspace?section=library&kind=word&q=abandon",
      expect: ["Library", "abandon", detail, "Move Back to Inbox"],
    },
    pageHeaders,
  );

  await runCheck(
    {
      label: "chain review route",
      path: "/workspace?section=review&kind=word",
      expect: ["Review", "Sources", "Question types", "abandon", detail],
    },
    pageHeaders,
  );

  console.log("ok - Lookup -> Inbox -> Library -> Review chain");
}

async function runDictionaryContractCheck() {
  const readyData = await readJsonResponse(
    absoluteUrl(dictApiBaseUrl, "/ready"),
    {},
    "dictionary readiness",
  );
  if (readyData?.ready !== true || readyData?.storage?.activity_store?.available !== true) {
    throw new Error("Dictionary readiness did not report a usable production health state");
  }

  console.log("ok - dictionary readiness");

  const lookupData = await readJsonResponse(
    absoluteUrl(dictApiBaseUrl, "/lookup?q=%E5%BD%BB%E5%BA%95"),
    {},
    "Chinese lookup contract",
  );
  const reverseItems = lookupData?.data?.reverse_items ?? [];
  const reverseTerms = reverseItems.map((item) => item.headword);
  if (lookupData?.data?.mode !== "reverse" || !reverseTerms.includes("complete")) {
    throw new Error("Chinese lookup contract did not return reverse candidates for 彻底");
  }

  console.log("ok - Chinese lookup contract");
}

async function main() {
  await runDictionaryContractCheck();
  for (const check of checks) {
    await runCheck(check);
  }
  await runWorkspaceChainCheck();

  console.log(`workspace smoke passed against ${baseUrl}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
