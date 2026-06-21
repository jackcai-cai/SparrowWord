export type LookupKind = "word" | "phrase" | "sentence";

export type LookupResult = {
  headword: string;
  pronunciation: string;
  level: string;
  summary: string;
  sourceTags: string[];
  meaningGroups: Array<{
    partOfSpeech: string;
    definitions: string[];
  }>;
  examples: Array<{
    english: string;
    chinese: string;
  }>;
  collocations: string[];
  relatedTerms: string[];
  englishDefinitions: string[];
  inflectionLines: string[];
  contextText: string;
};

export type SuggestionItem = {
  term: string;
  kind: "correction" | "related" | "phrase" | "starter";
  hint: string;
};

export type ReverseLookupMatch = {
  term: string;
  partOfSpeech: string;
  gloss: string;
  note: string;
};

export type ActivityHistoryStatus = "inProgress" | "completed" | "cancelled" | "failed";

export type ActivityInboxAction =
  | "createdInbox"
  | "updatedInbox"
  | "skippedExistingLibrary"
  | "historyOnly"
  | "awaitingCandidateSelection";

export type ActivityMeta = {
  originalQuery?: string;
  sourceLabel?: string;
  modelName?: string | null;
  lookupKind?: LookupKind;
  lookupMode?: WorkspaceState["mode"];
  inboxAction?: ActivityInboxAction;
  status?: ActivityHistoryStatus;
  statusMessage?: string | null;
};

export type ActivityItem = {
  id: string;
  term: string;
  detail: string;
  context?: string;
  savedAt: number;
  meta?: ActivityMeta | null;
};

export type WorkspaceState = {
  mode: "empty" | "lookup" | "reverse" | "no-result";
  kind: LookupKind;
  query: string;
  sourceLabel: string | null;
  lookup: LookupResult | null;
  suggestions: SuggestionItem[];
  reverseMatches: ReverseLookupMatch[];
  statusTitle: string;
  statusBody: string;
};

type LookupRecord = LookupResult & {
  aliases?: string[];
};

const lookupEntries: LookupRecord[] = [
  {
    headword: "abandon",
    pronunciation: "/əˈbæn.dən/",
    level: "B2",
    summary: "to leave something behind, or to stop supporting an idea, plan, or person",
    sourceTags: ["ECDICT", "Oewn", "Fake data"],
    meaningGroups: [
      {
        partOfSpeech: "verb",
        definitions: [
          "to leave a place, thing, or person and not return",
          "to stop doing or supporting something that you started",
        ],
      },
      {
        partOfSpeech: "noun phrase use",
        definitions: [
          "often appears in writing about losing restraint or acting freely",
        ],
      },
    ],
    examples: [
      {
        english: "They had to abandon the original plan after the budget was cut.",
        chinese: "预算被砍之后，他们只好放弃原来的计划。",
      },
      {
        english: "She never fully abandoned her interest in literature.",
        chinese: "她从未真正放下对文学的兴趣。",
      },
    ],
    collocations: [
      "abandon a plan",
      "abandon hope",
      "abandon a project",
      "with reckless abandon",
    ],
    relatedTerms: ["give up", "leave behind", "drop", "desert"],
    englishDefinitions: [
      "to leave behind completely",
      "to stop supporting or continuing",
    ],
    inflectionLines: ["abandon · abandons · abandoned · abandoning"],
    contextText: "They had to abandon the original plan after the budget was cut.",
    aliases: ["abandon hope", "with reckless abandon"],
  },
  {
    headword: "resilient",
    pronunciation: "/rɪˈzɪl.jənt/",
    level: "B2",
    summary: "able to recover quickly after stress, setbacks, or change",
    sourceTags: ["ECDICT", "Learner tone", "Fake data"],
    meaningGroups: [
      {
        partOfSpeech: "adjective",
        definitions: [
          "able to become strong, healthy, or successful again after difficulty",
          "able to return to the original shape after being bent or stretched",
        ],
      },
    ],
    examples: [
      {
        english: "A resilient student can reset after one bad test and keep moving.",
        chinese: "有韧性的学生能在一次考砸后重新调整并继续前进。",
      },
      {
        english: "Small teams can be surprisingly resilient when plans change fast.",
        chinese: "当计划快速变化时，小团队往往出人意料地有韧性。",
      },
    ],
    collocations: ["highly resilient", "emotionally resilient", "resilient system"],
    relatedTerms: ["adaptable", "tough", "flexible"],
    englishDefinitions: [
      "able to recover quickly from difficult conditions",
      "able to return to an original shape after pressure",
    ],
    inflectionLines: [],
    contextText: "Small teams can be surprisingly resilient when plans change fast.",
    aliases: ["resiliant"],
  },
  {
    headword: "withstand",
    pronunciation: "/wɪðˈstænd/",
    level: "B2",
    summary: "to remain strong against pressure, force, or criticism",
    sourceTags: ["ECDICT", "Reading notes", "Fake data"],
    meaningGroups: [
      {
        partOfSpeech: "verb",
        definitions: [
          "to resist something successfully without being damaged or defeated",
        ],
      },
    ],
    examples: [
      {
        english: "The bridge was built to withstand severe weather.",
        chinese: "这座桥的建造标准是要能承受恶劣天气。",
      },
      {
        english: "Her argument could not withstand close scrutiny.",
        chinese: "她的论点经不起仔细推敲。",
      },
    ],
    collocations: ["withstand pressure", "withstand criticism", "withstand heat"],
    relatedTerms: ["endure", "resist", "hold up"],
    englishDefinitions: ["to resist or survive something harmful"],
    inflectionLines: ["withstand · withstands · withstood · withstanding"],
    contextText: "Her argument could not withstand close scrutiny.",
  },
  {
    headword: "setback",
    pronunciation: "/ˈset.bæk/",
    level: "B1",
    summary: "a problem that delays or reverses progress for a while",
    sourceTags: ["ECDICT", "Exam tone", "Fake data"],
    meaningGroups: [
      {
        partOfSpeech: "noun",
        definitions: [
          "something that happens which delays progress or makes a situation worse",
        ],
      },
    ],
    examples: [
      {
        english: "The launch faced a minor setback, but the team adjusted quickly.",
        chinese: "发布遇到了一次小挫折，但团队很快就调整过来了。",
      },
    ],
    collocations: ["major setback", "face a setback", "temporary setback"],
    relatedTerms: ["obstacle", "delay", "difficulty"],
    englishDefinitions: ["a difficulty that delays progress"],
    inflectionLines: ["setback · setbacks"],
    contextText: "The launch faced a minor setback, but the team adjusted quickly.",
  },
];

const reverseLookupIndex: Record<string, ReverseLookupMatch[]> = {
  "放弃": [
    {
      term: "abandon",
      partOfSpeech: "verb",
      gloss: "to give up or leave behind",
      note: "best direct match for 放弃 in most reading contexts",
    },
    {
      term: "drop",
      partOfSpeech: "verb",
      gloss: "to stop continuing something",
      note: "lighter and more conversational",
    },
    {
      term: "let go of",
      partOfSpeech: "phrase",
      gloss: "to stop holding onto an idea or emotion",
      note: "better for emotional or abstract contexts",
    },
  ],
};

const defaultReverseMatches = reverseLookupIndex["放弃"] ?? [];

const defaultSuggestions: SuggestionItem[] = [
  {
    term: "abandon",
    kind: "starter",
    hint: "good starter query for reading-style dictionary output",
  },
  {
    term: "resilient",
    kind: "starter",
    hint: "shows adjective layout, examples, and collocations",
  },
  {
    term: "放弃",
    kind: "starter",
    hint: "tests reverse lookup from Chinese to English",
  },
  {
    term: "abnadon",
    kind: "starter",
    hint: "tests typo recovery and suggestion quality",
  },
];

const suggestionIndex: Record<string, SuggestionItem[]> = {
  abandon: [
    {
      term: "abandonment",
      kind: "related",
      hint: "useful when you want the noun form in writing notes",
    },
    {
      term: "abandon a plan",
      kind: "phrase",
      hint: "common phrase in study and news writing",
    },
    {
      term: "with reckless abandon",
      kind: "phrase",
      hint: "useful phrase when style and tone matter",
    },
  ],
  resilient: [
    {
      term: "resiliant",
      kind: "correction",
      hint: "common misspelling worth catching immediately",
    },
    {
      term: "resilience",
      kind: "related",
      hint: "noun form that often appears in essays and psychology texts",
    },
    {
      term: "highly resilient",
      kind: "phrase",
      hint: "common collocation in academic and business writing",
    },
  ],
  withstand: [
    {
      term: "withstand pressure",
      kind: "phrase",
      hint: "common exam and workplace phrasing",
    },
    {
      term: "endure",
      kind: "related",
      hint: "nearby verb with a different tone",
    },
  ],
  setback: [
    {
      term: "face a setback",
      kind: "phrase",
      hint: "common way this noun appears in real passages",
    },
    {
      term: "obstacle",
      kind: "related",
      hint: "useful contrast if you need a broader term",
    },
  ],
  abnadon: [
    {
      term: "abandon",
      kind: "correction",
      hint: "closest correction for the misspelt input",
    },
    {
      term: "abandon a plan",
      kind: "phrase",
      hint: "good next click to understand usage quickly",
    },
  ],
  resiliant: [
    {
      term: "resilient",
      kind: "correction",
      hint: "closest correction for the misspelt adjective",
    },
    {
      term: "resilience",
      kind: "related",
      hint: "noun form often searched together",
    },
  ],
  "放弃": [
    {
      term: "abandon",
      kind: "related",
      hint: "most direct English verb in neutral reading contexts",
    },
    {
      term: "let go of",
      kind: "phrase",
      hint: "better if the sentence is emotional or abstract",
    },
  ],
};

const activitySeedNow = Date.now();

export const recentHistory: ActivityItem[] = [
  {
    id: "h-1",
    term: "abandon",
    detail: "looked up from a policy article",
    savedAt: activitySeedNow - 2 * 60 * 1000,
  },
  {
    id: "h-2",
    term: "withstand",
    detail: "checked nuance in a science paragraph",
    savedAt: activitySeedNow - 16 * 60 * 1000,
  },
  {
    id: "h-3",
    term: "setback",
    detail: "saved after a mock reading passage",
    savedAt: activitySeedNow - 42 * 60 * 1000,
  },
];

export const inboxItems: ActivityItem[] = [
  {
    id: "i-1",
    term: "abandon hope",
    detail: "interesting phrase worth revisiting later",
    savedAt: activitySeedNow - 4 * 60 * 1000,
  },
  {
    id: "i-2",
    term: "with reckless abandon",
    detail: "idiomatic phrase that needs context memory",
    savedAt: activitySeedNow - 15 * 60 * 1000,
  },
  {
    id: "i-3",
    term: "resilient",
    detail: "candidate for later review set",
    savedAt: activitySeedNow - 28 * 60 * 1000,
  },
];

export const starterQueries = defaultSuggestions.map((item) => item.term);

function normalizeQuery(query: string): string {
  return query.trim().toLowerCase();
}

function lookupByQuery(query: string): LookupResult | null {
  const normalized = normalizeQuery(query);

  const directMatch = lookupEntries.find((entry) => entry.headword === normalized);
  if (directMatch) {
    return directMatch;
  }

  const aliasMatch = lookupEntries.find((entry) =>
    entry.aliases?.some((alias) => normalizeQuery(alias) === normalized),
  );

  return aliasMatch ?? null;
}

function resolveSourceLabel(source: string | null): string | null {
  if (!source) {
    return null;
  }

  const sourceLabels: Record<string, string> = {
    search: "Typed lookup",
    starter: "Starter query",
    history: "Recent history",
    inbox: "Quick Capture Draft",
    suggestion: "Suggestion click",
    reverse: "Reverse lookup",
  };

  return sourceLabels[source] ?? "Workspace action";
}

export function inferLookupKind(
  rawKind: string | null | undefined,
  rawQuery: string | null | undefined,
): LookupKind {
  if (rawKind === "word" || rawKind === "phrase" || rawKind === "sentence") {
    return rawKind;
  }

  const query = rawQuery?.trim() ?? "";
  if (!query) {
    return "word";
  }

  if (/[.!?。！？]/u.test(query) || query.split(/\s+/).filter(Boolean).length >= 6) {
    return "sentence";
  }

  if (query.includes(" ")) {
    return "phrase";
  }

  return "word";
}

export function resolveWorkspaceState(
  rawQuery: string | null | undefined,
  source: string | null | undefined,
  rawKind?: string | null,
): WorkspaceState {
  const query = rawQuery?.trim() ?? "";
  const kind = inferLookupKind(rawKind, rawQuery);
  const sourceLabel = resolveSourceLabel(source ?? null);

  if (!query) {
    return {
      mode: "empty",
      kind,
      query: "",
      sourceLabel,
      lookup: null,
      suggestions: defaultSuggestions,
      reverseMatches: defaultReverseMatches,
      statusTitle: "No lookup result yet.",
      statusBody: "Enter a word, phrase, Chinese query, or sentence.",
    };
  }

  const lookup = lookupByQuery(query);
  if (lookup) {
    return {
      mode: "lookup",
      kind,
      query,
      sourceLabel,
      lookup,
      suggestions: suggestionIndex[normalizeQuery(query)] ?? suggestionIndex[lookup.headword] ?? [],
      reverseMatches: defaultReverseMatches,
      statusTitle: `Showing ${lookup.headword}.`,
      statusBody: "Dictionary result.",
    };
  }

  const reverseMatches = reverseLookupIndex[query] ?? [];
  if (reverseMatches.length > 0) {
    const [topMatch] = reverseMatches;
    const bestMatch = topMatch ? lookupByQuery(topMatch.term) : null;

    return {
      mode: "reverse",
      kind,
      query,
      sourceLabel,
      lookup: bestMatch,
      suggestions: suggestionIndex[query] ?? defaultSuggestions.slice(0, 2),
      reverseMatches,
      statusTitle: `Reverse lookup found ${reverseMatches.length} English options.`,
      statusBody: "Select an English candidate to inspect or save.",
    };
  }

  return {
    mode: "no-result",
    kind,
    query,
    sourceLabel,
    lookup: null,
    suggestions: suggestionIndex[normalizeQuery(query)] ?? defaultSuggestions.slice(0, 3),
    reverseMatches: [],
    statusTitle: `No direct match for “${query}” yet.`,
    statusBody: "Try a suggestion or capture it manually.",
  };
}
