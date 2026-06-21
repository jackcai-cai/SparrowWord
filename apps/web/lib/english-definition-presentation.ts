export type EnglishDefinitionPresentation = {
  primaryDefinitions: string[];
  additionalDefinitions: string[];
  synonyms: string[];
};

function cleanDefinition(text: string): string {
  return text
    .replace(
      /^(?:(?:adj(?:ective)?(?:\s+satellite)?|adv(?:erb)?|noun|verb|vt|vi|v|n|a|s)\.?\s+)+/i,
      "",
    )
    .trim()
    .replace(/^[,;，；]+|[,;，；]+$/g, "")
    .trim();
}

function normalizedKey(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function containsNearDuplicate(candidate: string, existing: string[]): boolean {
  const candidateKey = normalizedKey(candidate);
  if (!candidateKey) {
    return true;
  }

  return existing.some((line) => {
    const existingKey = normalizedKey(line);
    return (
      existingKey === candidateKey ||
      existingKey.includes(candidateKey) ||
      candidateKey.includes(existingKey)
    );
  });
}

function appendUniqueTerms(terms: string[], target: string[]): void {
  for (const term of terms) {
    const cleaned = term.trim();
    if (!cleaned) {
      continue;
    }

    if (!target.some((item) => item.localeCompare(cleaned, undefined, { sensitivity: "accent" }) === 0)) {
      target.push(cleaned);
    }
  }
}

export function buildEnglishDefinitionPresentation(
  definitions: string[],
  synonyms: string[] = [],
  preferredVisibleCount = 2,
): EnglishDefinitionPresentation {
  const parsedDefinitions: string[] = [];
  const parsedSynonyms: string[] = [];

  for (const definition of definitions) {
    const trimmed = definition.trim();
    if (!trimmed) {
      continue;
    }

    if (trimmed.toLowerCase().startsWith("synonyms:")) {
      const raw = trimmed.slice("Synonyms:".length);
      appendUniqueTerms(
        raw
          .split(/[,;，；]/)
          .map((term) => term.trim()),
        parsedSynonyms,
      );
      continue;
    }

    const cleaned = cleanDefinition(trimmed);
    if (!cleaned) {
      continue;
    }

    if (!containsNearDuplicate(cleaned, parsedDefinitions)) {
      parsedDefinitions.push(cleaned);
    }
  }

  appendUniqueTerms(synonyms, parsedSynonyms);

  return {
    primaryDefinitions: parsedDefinitions.slice(0, preferredVisibleCount),
    additionalDefinitions: parsedDefinitions.slice(preferredVisibleCount),
    synonyms: parsedSynonyms,
  };
}

export function splitPronunciationLines(pronunciation: string): string[] {
  const trimmed = pronunciation.trim();
  if (!trimmed) {
    return [];
  }

  const match = trimmed.match(/BrE\s+(.+?),\s*AmE\s+(.+)$/i);
  if (match) {
    const [, bre, ame] = match;
    return [`BrE ${bre?.trim() ?? ""}`, `AmE ${ame?.trim() ?? ""}`].filter((line) => line.trim().length > 4);
  }

  return [trimmed];
}
