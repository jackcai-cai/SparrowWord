import type { LookupKind, LookupResult } from "./mock-workspace";

export const editableMeaningChoiceCount = 5;
export const editableExampleChoiceCount = 3;

export type MeaningCandidate = {
  id: string;
  partOfSpeech: string;
  meaning: string;
  selected: boolean;
};

export type WorkspaceEditableEntry = {
  kind: LookupKind;
  term: string;
  partOfSpeech: string;
  detail: string;
  meaningCandidates?: MeaningCandidate[];
  meaningChoices: string[];
  meaningChoicePartOfSpeechLabels: string[];
  selectedMeaningIndexes: number[];
  exampleChoices: string[];
  selectedExampleIndexes: number[];
  englishDefinitions: string[];
  inflectionLines: string[];
  referenceTags: string[];
  notes: string;
};

export type WorkspaceEditableEntryMap = Record<string, WorkspaceEditableEntry>;

export type EditableChoiceState = {
  choices: string[];
  selectedIndexes: number[];
  labels?: string[];
};

function normalizedKey(text: string): string {
  return text
    .trim()
    .replace(/\s+/g, " ")
    .toLowerCase();
}

export function sanitizeInlineText(text: string | undefined, fallback = ""): string {
  const cleaned = text?.trim().replace(/\s+/g, " ") ?? "";
  return cleaned || fallback;
}

export function sanitizeParagraphText(text: string | undefined): string {
  return text?.trim().replace(/\r\n/g, "\n") ?? "";
}

export function inferLookupKindFromTerm(term: string, fallback: LookupKind = "word"): LookupKind {
  const trimmed = term.trim();
  if (!trimmed) {
    return fallback;
  }

  if (/[.!?。！？]/u.test(trimmed) || trimmed.split(/\s+/).filter(Boolean).length >= 6) {
    return "sentence";
  }

  if (trimmed.includes(" ")) {
    return "phrase";
  }

  return fallback;
}

function uniqueNonEmpty(items: string[], limit?: number): string[] {
  const seen = new Set<string>();
  const next: string[] = [];

  for (const item of items) {
    const cleaned = sanitizeInlineText(item);
    if (!cleaned) {
      continue;
    }

    const key = normalizedKey(cleaned);
    if (!key || seen.has(key)) {
      continue;
    }

    seen.add(key);
    next.push(cleaned);

    if (typeof limit === "number" && next.length >= limit) {
      break;
    }
  }

  return next;
}

function normalizedIndexes(indexes: number[], upperBound: number): number[] {
  const seen = new Set<number>();
  const next: number[] = [];

  for (const index of indexes) {
    if (!Number.isInteger(index) || index < 0 || index >= upperBound || seen.has(index)) {
      continue;
    }

    seen.add(index);
    next.push(index);
  }

  return next;
}

function selectedTexts(items: string[], indexes: number[]): string[] {
  return normalizedIndexes(indexes, items.length).map((index) => items[index] ?? "").filter(Boolean);
}

function stableMeaningCandidateId(index: number, meaning: string, partOfSpeech: string): string {
  const key = [normalizedKey(partOfSpeech), normalizedKey(meaning), String(index)].join("::");
  return key || `sense::${index}`;
}

export function meaningCandidatesFromChoices(
  choices: string[],
  labels: string[],
  selectedIndexes: number[],
): MeaningCandidate[] {
  const normalizedSelectedIndexes = new Set(normalizedIndexes(selectedIndexes, choices.length));

  return choices
    .map((choice, index) => {
      const cleanedMeaning = sanitizeInlineText(choice);
      if (!cleanedMeaning) {
        return null;
      }

      const cleanedPartOfSpeech = sanitizeInlineText(labels[index] ?? "");
      return {
        id: stableMeaningCandidateId(index, cleanedMeaning, cleanedPartOfSpeech),
        partOfSpeech: cleanedPartOfSpeech,
        meaning: cleanedMeaning,
        selected: normalizedSelectedIndexes.has(index),
      } satisfies MeaningCandidate;
    })
    .filter((item): item is MeaningCandidate => item !== null);
}

function normalizeMeaningCandidates(
  candidates: MeaningCandidate[],
  fallbackChoices: string[],
  fallbackLabels: string[],
  fallbackSelectedIndexes: number[],
  fallbackDetail: string,
): MeaningCandidate[] {
  const baseCandidates =
    candidates.length > 0
      ? candidates
      : meaningCandidatesFromChoices(fallbackChoices, fallbackLabels, fallbackSelectedIndexes);

  const normalizedCandidates: MeaningCandidate[] = [];
  let hasSelected = false;

  for (const [index, candidate] of baseCandidates.entries()) {
    const cleanedMeaning = sanitizeInlineText(candidate.meaning);
    const cleanedPartOfSpeech = sanitizeInlineText(candidate.partOfSpeech);
    if (!cleanedMeaning) {
      continue;
    }

    const existingIndex = normalizedCandidates.findIndex(
      (item) =>
        normalizedKey(item.partOfSpeech) === normalizedKey(cleanedPartOfSpeech) &&
        normalizedKey(item.meaning) === normalizedKey(cleanedMeaning),
    );

    if (existingIndex >= 0) {
      if (candidate.selected) {
        const existingCandidate = normalizedCandidates[existingIndex];
        if (!existingCandidate) {
          continue;
        }
        normalizedCandidates[existingIndex] = {
          id: existingCandidate.id,
          partOfSpeech: existingCandidate.partOfSpeech,
          meaning: existingCandidate.meaning,
          selected: true,
        };
        hasSelected = true;
      }
      continue;
    }

    normalizedCandidates.push({
      id: sanitizeInlineText(candidate.id, stableMeaningCandidateId(index, cleanedMeaning, cleanedPartOfSpeech)),
      partOfSpeech: cleanedPartOfSpeech,
      meaning: cleanedMeaning,
      selected: Boolean(candidate.selected),
    });
    if (candidate.selected) {
      hasSelected = true;
    }

    if (normalizedCandidates.length >= editableMeaningChoiceCount) {
      break;
    }
  }

  if (normalizedCandidates.length === 0) {
    const fallbackMeaning = sanitizeInlineText(fallbackDetail);
    if (!fallbackMeaning) {
      return [];
    }

    return [
      {
        id: stableMeaningCandidateId(0, fallbackMeaning, ""),
        partOfSpeech: "",
        meaning: fallbackMeaning,
        selected: true,
      },
    ];
  }

  if (!hasSelected) {
    const firstCandidate = normalizedCandidates[0];
    if (firstCandidate) {
      normalizedCandidates[0] = {
        id: firstCandidate.id,
        partOfSpeech: firstCandidate.partOfSpeech,
        meaning: firstCandidate.meaning,
        selected: true,
      };
    }
  }

  return normalizedCandidates;
}

function contextualMeaningScore(
  term: string,
  choice: string,
  label: string,
  context: string | undefined,
): number {
  const normalizedTerm = normalizedKey(term);
  const normalizedContext = normalizedKey(context ?? "");
  if (!normalizedContext) {
    return 0;
  }

  if (normalizedTerm !== "charge") {
    return 0;
  }

  const feeSignal = /\b(fee|fees|cost|costs|price|prices|bill|bills|bank|banking|delivery|payment|payments|pay|paid|fare|fares)\b/i;
  const accusationSignal = /\b(accuse|accused|accusing|court|courts|police|crime|criminal|lawsuit|lawsuits|prosecutor|prosecution|indict|indicted)\b/i;
  const powerSignal = /\b(battery|batteries|phone|phones|laptop|laptops|plug|plugged|usb|electric|electricity|power|powered|recharge)\b/i;

  let dominantSignal: "fee" | "accusation" | "power" | null = null;
  if (feeSignal.test(normalizedContext)) {
    dominantSignal = "fee";
  } else if (accusationSignal.test(normalizedContext)) {
    dominantSignal = "accusation";
  } else if (powerSignal.test(normalizedContext)) {
    dominantSignal = "power";
  }

  if (!dominantSignal) {
    return 0;
  }

  let score = 0;
  if (dominantSignal === "fee") {
    if (/(收费|要价|费用|账单)/.test(choice)) {
      score += 40;
    }
    if (/verb/i.test(label)) {
      score += 8;
    }
    if (/收费/.test(choice)) {
      score += 10;
    } else if (/要价/.test(choice)) {
      score += 6;
    }
  } else if (dominantSignal === "accusation") {
    if (/(指控|控诉|加罪)/.test(choice)) {
      score += 40;
    }
    if (/(noun|verb)/i.test(label)) {
      score += 4;
    }
  } else if (dominantSignal === "power") {
    if (/(充电|电荷)/.test(choice)) {
      score += 40;
    }
    if (/verb/i.test(label)) {
      score += 4;
    }
  }

  return score;
}

function contextSensitiveMeaningIndexes(
  term: string,
  choices: string[],
  labels: string[],
  context: string | undefined,
): number[] {
  let bestScore = Number.NEGATIVE_INFINITY;
  let bestIndex = -1;

  for (const [index, choice] of choices.entries()) {
    const score = contextualMeaningScore(term, choice, labels[index] ?? "", context);
    if (score > bestScore) {
      bestScore = score;
      bestIndex = index;
    }
  }

  return bestScore > 0 && bestIndex >= 0 ? [bestIndex] : [];
}

export function dedupeEditableChoiceState(state: EditableChoiceState): EditableChoiceState {
  const nextChoices: string[] = [];
  const nextLabels: string[] = [];
  const firstIndexByKey = new Map<string, number>();
  const remappedIndexes = new Map<number, number>();

  state.choices.forEach((choice, index) => {
    const cleaned = sanitizeInlineText(choice);
    const key = normalizedKey(cleaned);
    if (!cleaned || !key) {
      return;
    }

    const existingIndex = firstIndexByKey.get(key);
    if (typeof existingIndex === "number") {
      remappedIndexes.set(index, existingIndex);
      return;
    }

    const nextIndex = nextChoices.length;
    firstIndexByKey.set(key, nextIndex);
    remappedIndexes.set(index, nextIndex);
    nextChoices.push(cleaned);
    if (state.labels) {
      nextLabels.push(sanitizeInlineText(state.labels[index] ?? ""));
    }
  });

  const nextSelectedIndexes = normalizedIndexes(
    state.selectedIndexes.map((index) => remappedIndexes.get(index) ?? -1).filter((index) => index >= 0),
    nextChoices.length,
  );

  return {
    choices: nextChoices,
    selectedIndexes: nextSelectedIndexes,
    labels: state.labels ? nextLabels : undefined,
  };
}

export function keepOnlySelectedEditableChoices(state: EditableChoiceState): EditableChoiceState {
  const selectedIndexes = normalizedIndexes(state.selectedIndexes, state.choices.length);
  const nextChoices = selectedIndexes.map((index) => sanitizeInlineText(state.choices[index] ?? "")).filter(Boolean);
  const nextLabels = state.labels
    ? selectedIndexes.map((index) => sanitizeInlineText(state.labels?.[index] ?? ""))
    : undefined;

  return dedupeEditableChoiceState({
    choices: nextChoices,
    selectedIndexes: nextChoices.map((_, index) => index),
    labels: nextLabels,
  });
}

export function reorderEditableChoiceState(
  state: EditableChoiceState,
  fromIndex: number,
  toIndex: number,
): EditableChoiceState {
  if (
    fromIndex === toIndex ||
    fromIndex < 0 ||
    toIndex < 0 ||
    fromIndex >= state.choices.length ||
    toIndex >= state.choices.length
  ) {
    return state;
  }

  const order = state.choices.map((_, index) => index);
  const [moved] = order.splice(fromIndex, 1);
  if (typeof moved !== "number") {
    return state;
  }
  order.splice(toIndex, 0, moved);

  const indexMap = new Map<number, number>();
  order.forEach((originalIndex, nextIndex) => {
    indexMap.set(originalIndex, nextIndex);
  });

  const nextChoices = order.map((index) => state.choices[index] ?? "");
  const nextLabels = state.labels ? order.map((index) => sanitizeInlineText(state.labels?.[index] ?? "")) : undefined;
  const nextSelectedIndexes = normalizedIndexes(
    state.selectedIndexes.map((index) => indexMap.get(index) ?? -1).filter((index) => index >= 0),
    nextChoices.length,
  );

  return {
    choices: nextChoices,
    selectedIndexes: nextSelectedIndexes,
    labels: nextLabels,
  };
}

function flattenMeaningSnapshot(
  snapshot: LookupResult | null | undefined,
  term: string,
  context: string | undefined,
): {
  partOfSpeech: string;
  choices: string[];
  labels: string[];
} {
  if (!snapshot) {
    return {
      partOfSpeech: "",
      choices: [],
      labels: [],
    };
  }

  const ranked: Array<{ choice: string; label: string; originalIndex: number; score: number }> = [];
  const seen = new Set<string>();
  let originalIndex = 0;

  for (const group of snapshot.meaningGroups) {
    for (const definition of group.definitions) {
      const cleaned = sanitizeInlineText(definition);
      const key = normalizedKey(cleaned);
      if (!cleaned || !key || seen.has(key)) {
        continue;
      }

      seen.add(key);
      const label = sanitizeInlineText(group.partOfSpeech);
      ranked.push({
        choice: cleaned,
        label,
        originalIndex,
        score: contextualMeaningScore(term, cleaned, label, context),
      });
      originalIndex += 1;
    }
  }

  const prioritized = [...ranked].sort((left, right) => {
    if (right.score !== left.score) {
      return right.score - left.score;
    }

    return left.originalIndex - right.originalIndex;
  });

  const choices = prioritized.slice(0, editableMeaningChoiceCount).map((item) => item.choice);
  const labels = prioritized.slice(0, editableMeaningChoiceCount).map((item) => item.label);

  return {
    partOfSpeech: sanitizeInlineText(snapshot.meaningGroups[0]?.partOfSpeech),
    choices,
    labels,
  };
}

function mergeMeaningCandidates(
  snapshotChoices: string[],
  snapshotLabels: string[],
  existingChoices: string[],
  existingLabels: string[],
  fallbackDetail: string,
): {
  choices: string[];
  labels: string[];
} {
  const choices = [...snapshotChoices];
  const labels = [...snapshotLabels];
  const seen = new Set(snapshotChoices.map((choice) => normalizedKey(choice)));

  const appendCandidate = (text: string, label: string) => {
    const cleaned = sanitizeInlineText(text);
    const key = normalizedKey(cleaned);
    if (!cleaned || !key || seen.has(key) || choices.length >= editableMeaningChoiceCount) {
      return;
    }

    seen.add(key);
    choices.push(cleaned);
    labels.push(sanitizeInlineText(label));
  };

  existingChoices.forEach((choice, index) => appendCandidate(choice, existingLabels[index] ?? ""));
  appendCandidate(fallbackDetail, "");

  return {
    choices,
    labels: labels.slice(0, choices.length),
  };
}

function mergeExampleCandidates(snapshot: LookupResult | null | undefined, existingChoices: string[]): string[] {
  const snapshotChoices = snapshot?.examples.map((example) => example.english) ?? [];
  return uniqueNonEmpty([...snapshotChoices, ...existingChoices], editableExampleChoiceCount);
}

function mapSelectedTextsToIndexes(
  choices: string[],
  preferredTexts: string[],
  fallbackDetail: string,
): number[] {
  const indexes = preferredTexts
    .map((text) => {
      const key = normalizedKey(text);
      return choices.findIndex((choice) => normalizedKey(choice) === key);
    })
    .filter((index) => index >= 0);

  if (indexes.length > 0) {
    return normalizedIndexes(indexes, choices.length);
  }

  const fallbackKey = normalizedKey(fallbackDetail);
  if (fallbackKey) {
    const fallbackIndex = choices.findIndex((choice) => normalizedKey(choice) === fallbackKey);
    if (fallbackIndex >= 0) {
      return [fallbackIndex];
    }
  }

  return choices.length > 0 ? [0] : [];
}

function detailFromSelection(choices: string[], indexes: number[], fallbackDetail: string): string {
  const selected = selectedTexts(choices, indexes);
  if (selected.length > 0) {
    return selected.join(" / ");
  }

  return sanitizeInlineText(fallbackDetail, choices[0] ?? "");
}

function partOfSpeechFromSelection(
  labels: string[],
  indexes: number[],
  fallbackPartOfSpeech: string,
): string {
  const selectedLabel = normalizedIndexes(indexes, labels.length)
    .map((index) => sanitizeInlineText(labels[index]))
    .find(Boolean);

  return sanitizeInlineText(selectedLabel, fallbackPartOfSpeech);
}

export function selectedMeaningsFromEntry(entry: Pick<WorkspaceEditableEntry, "meaningChoices" | "selectedMeaningIndexes">): string[] {
  const candidates = (entry as WorkspaceEditableEntry).meaningCandidates;
  if (Array.isArray(candidates) && candidates.length > 0) {
    return candidates
      .filter((candidate) => candidate.selected)
      .map((candidate) => sanitizeInlineText(candidate.meaning))
      .filter(Boolean);
  }

  const meaningChoices = Array.isArray((entry as WorkspaceEditableEntry).meaningChoices)
    ? (entry as WorkspaceEditableEntry).meaningChoices
    : [];
  const selectedMeaningIndexes = Array.isArray((entry as WorkspaceEditableEntry).selectedMeaningIndexes)
    ? (entry as WorkspaceEditableEntry).selectedMeaningIndexes
    : [];

  return selectedTexts(meaningChoices, selectedMeaningIndexes);
}

export function selectedExamplesFromEntry(entry: Pick<WorkspaceEditableEntry, "exampleChoices" | "selectedExampleIndexes">): string[] {
  const exampleChoices = Array.isArray((entry as WorkspaceEditableEntry).exampleChoices)
    ? (entry as WorkspaceEditableEntry).exampleChoices
    : [];
  const selectedExampleIndexes = Array.isArray((entry as WorkspaceEditableEntry).selectedExampleIndexes)
    ? (entry as WorkspaceEditableEntry).selectedExampleIndexes
    : [];

  return selectedTexts(exampleChoices, selectedExampleIndexes);
}

export function finalizeEditableEntrySelection(entry: WorkspaceEditableEntry): WorkspaceEditableEntry {
  const meaningState = keepOnlySelectedEditableChoices({
    choices: entry.meaningChoices,
    selectedIndexes: entry.selectedMeaningIndexes,
    labels: entry.meaningChoicePartOfSpeechLabels,
  });
  const finalizedMeaningState =
    meaningState.choices.length > 0
      ? meaningState
      : {
          choices: [sanitizeInlineText(entry.detail, entry.term)].filter(Boolean),
          selectedIndexes: sanitizeInlineText(entry.detail, entry.term) ? [0] : [],
          labels: entry.partOfSpeech ? [entry.partOfSpeech] : [],
        };
  const exampleState = keepOnlySelectedEditableChoices({
    choices: entry.exampleChoices,
    selectedIndexes: entry.selectedExampleIndexes,
  });

  return {
    ...entry,
    partOfSpeech: partOfSpeechFromSelection(
      finalizedMeaningState.labels ?? [],
      finalizedMeaningState.selectedIndexes,
      entry.partOfSpeech,
    ),
    detail: detailFromSelection(
      finalizedMeaningState.choices,
      finalizedMeaningState.selectedIndexes,
      entry.detail,
    ),
    meaningCandidates: meaningCandidatesFromChoices(
      finalizedMeaningState.choices,
      finalizedMeaningState.labels ?? [],
      finalizedMeaningState.selectedIndexes,
    ),
    meaningChoices: finalizedMeaningState.choices,
    meaningChoicePartOfSpeechLabels: finalizedMeaningState.labels ?? [],
    selectedMeaningIndexes: finalizedMeaningState.selectedIndexes,
    exampleChoices: exampleState.choices,
    selectedExampleIndexes: exampleState.selectedIndexes,
  };
}

export function createEditableEntry(
  options: {
    term: string;
    kind?: LookupKind;
    detail?: string;
    context?: string;
    notes?: string;
    snapshot?: LookupResult | null;
    existing?: Partial<WorkspaceEditableEntry> | null;
  },
): WorkspaceEditableEntry {
  const existing = options.existing ?? {};
  const term = sanitizeInlineText(options.term, sanitizeInlineText(existing.term));
  const fallbackDetail = sanitizeInlineText(options.detail, sanitizeInlineText(existing.detail, term));
  const snapshotInfo = flattenMeaningSnapshot(options.snapshot, term, options.context);
  const mergedMeanings = mergeMeaningCandidates(
    snapshotInfo.choices,
    snapshotInfo.labels,
    existing.meaningChoices ?? [],
    existing.meaningChoicePartOfSpeechLabels ?? [],
    fallbackDetail,
  );
  const selectedMeaningTexts = selectedMeaningsFromEntry(existing as Pick<
    WorkspaceEditableEntry,
    "meaningChoices" | "selectedMeaningIndexes"
  >);
  const fallbackSelectedMeaningIndexes =
    selectedMeaningTexts.length > 0
      ? mapSelectedTextsToIndexes(
          mergedMeanings.choices,
          selectedMeaningTexts,
          fallbackDetail,
        )
      : (() => {
          const contextualIndexes = contextSensitiveMeaningIndexes(
            term,
            mergedMeanings.choices,
            mergedMeanings.labels,
            options.context,
          );
          return contextualIndexes.length > 0 ? contextualIndexes : [0];
        })();
  const meaningCandidates = normalizeMeaningCandidates(
    Array.isArray(existing.meaningCandidates) ? existing.meaningCandidates : [],
    mergedMeanings.choices,
    mergedMeanings.labels,
    fallbackSelectedMeaningIndexes,
    fallbackDetail,
  );
  const meaningChoices = meaningCandidates.map((candidate) => candidate.meaning);
  const meaningChoicePartOfSpeechLabels = meaningCandidates.map((candidate) => candidate.partOfSpeech);
  const selectedMeaningIndexes = meaningCandidates
    .map((candidate, index) => (candidate.selected ? index : -1))
    .filter((index) => index >= 0);
  const exampleChoices = mergeExampleCandidates(options.snapshot, existing.exampleChoices ?? []);
  const selectedExampleTexts = selectedExamplesFromEntry({
    exampleChoices: existing.exampleChoices ?? [],
    selectedExampleIndexes: existing.selectedExampleIndexes ?? [],
  });
  const selectedExampleIndexes = normalizedIndexes(
    selectedExampleTexts
      .map((text) => {
        const key = normalizedKey(text);
        return exampleChoices.findIndex((choice) => normalizedKey(choice) === key);
      })
      .filter((index) => index >= 0),
    exampleChoices.length,
  );

  return {
    kind: existing.kind ?? options.kind ?? inferLookupKindFromTerm(term, "word"),
    term,
    partOfSpeech: partOfSpeechFromSelection(
      meaningChoicePartOfSpeechLabels,
      selectedMeaningIndexes,
      sanitizeInlineText(existing.partOfSpeech, snapshotInfo.partOfSpeech),
    ),
    detail: detailFromSelection(meaningChoices, selectedMeaningIndexes, fallbackDetail),
    meaningCandidates,
    meaningChoices,
    meaningChoicePartOfSpeechLabels,
    selectedMeaningIndexes,
    exampleChoices,
    selectedExampleIndexes:
      selectedExampleIndexes.length > 0
        ? selectedExampleIndexes
        : exampleChoices.length > 0
          ? [0]
          : [],
    englishDefinitions: uniqueNonEmpty(
      options.snapshot?.englishDefinitions ?? existing.englishDefinitions ?? [],
    ),
    inflectionLines: uniqueNonEmpty(options.snapshot?.inflectionLines ?? existing.inflectionLines ?? []),
    referenceTags: uniqueNonEmpty(options.snapshot?.sourceTags ?? existing.referenceTags ?? []),
    notes: sanitizeParagraphText(options.notes ?? existing.notes ?? ""),
  };
}

export function parseStoredEditableEntryMap(value: unknown): WorkspaceEditableEntryMap {
  if (!value || typeof value !== "object") {
    return {};
  }

  const parsed: WorkspaceEditableEntryMap = {};

  for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
    if (!item || typeof item !== "object") {
      continue;
    }

    const record = item as Partial<WorkspaceEditableEntry>;
    const term = typeof record.term === "string" ? record.term : "";
    if (!term.trim()) {
      continue;
    }

    const entry = createEditableEntry({
      term,
      kind: record.kind,
      detail: typeof record.detail === "string" ? record.detail : term,
      notes: typeof record.notes === "string" ? record.notes : "",
      existing: {
        ...record,
        meaningCandidates: Array.isArray((record as { meaningCandidates?: unknown[] }).meaningCandidates)
          ? (record as { meaningCandidates?: unknown[] }).meaningCandidates
              ?.map((candidate, index) => {
                if (!candidate || typeof candidate !== "object") {
                  return null;
                }

                const value = candidate as Partial<MeaningCandidate>;
                const cleanedMeaning = typeof value.meaning === "string" ? sanitizeInlineText(value.meaning) : "";
                if (!cleanedMeaning) {
                  return null;
                }

                const cleanedPartOfSpeech =
                  typeof value.partOfSpeech === "string" ? sanitizeInlineText(value.partOfSpeech) : "";

                return {
                  id:
                    typeof value.id === "string" && value.id.trim().length > 0
                      ? value.id
                      : stableMeaningCandidateId(index, cleanedMeaning, cleanedPartOfSpeech),
                  partOfSpeech: cleanedPartOfSpeech,
                  meaning: cleanedMeaning,
                  selected: Boolean(value.selected),
                } satisfies MeaningCandidate;
              })
              .filter((candidate): candidate is MeaningCandidate => candidate !== null)
          : [],
        meaningChoices: Array.isArray(record.meaningChoices) ? record.meaningChoices.filter((value): value is string => typeof value === "string") : [],
        meaningChoicePartOfSpeechLabels: Array.isArray(record.meaningChoicePartOfSpeechLabels)
          ? record.meaningChoicePartOfSpeechLabels.filter((value): value is string => typeof value === "string")
          : [],
        selectedMeaningIndexes: Array.isArray(record.selectedMeaningIndexes)
          ? record.selectedMeaningIndexes.filter((value): value is number => typeof value === "number")
          : [],
        exampleChoices: Array.isArray(record.exampleChoices) ? record.exampleChoices.filter((value): value is string => typeof value === "string") : [],
        selectedExampleIndexes: Array.isArray(record.selectedExampleIndexes)
          ? record.selectedExampleIndexes.filter((value): value is number => typeof value === "number")
          : [],
        englishDefinitions: Array.isArray(record.englishDefinitions)
          ? record.englishDefinitions.filter((value): value is string => typeof value === "string")
          : [],
        inflectionLines: Array.isArray(record.inflectionLines)
          ? record.inflectionLines.filter((value): value is string => typeof value === "string")
          : [],
        referenceTags: Array.isArray(record.referenceTags)
          ? record.referenceTags.filter((value): value is string => typeof value === "string")
          : [],
      },
    });

    parsed[key] = entry;
  }

  return parsed;
}
