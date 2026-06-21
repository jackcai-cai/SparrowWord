import test from "node:test";
import assert from "node:assert/strict";

import {
  defaultWorkspacePreferences,
  parseStoredWorkspacePreferences,
  workspaceLayoutLimits,
} from "./workspace-preferences";

test("parseStoredWorkspacePreferences preserves legacy preference shape", () => {
  const preferences = parseStoredWorkspacePreferences({
    excludeMasteredFromReview: false,
    pronunciationVoiceURI: "voice://test",
  });

  assert.equal(preferences.excludeMasteredFromReview, false);
  assert.equal(preferences.isLibraryCleanMode, false);
  assert.deepEqual(preferences.layout, defaultWorkspacePreferences().layout);
  assert.equal(preferences.workspacePaneLayoutPreference, defaultWorkspacePreferences().workspacePaneLayoutPreference);
  assert.equal(preferences.showLookupReferenceTags, false);
  assert.equal(preferences.pronunciationVoiceURI, "voice://test");
  assert.deepEqual(preferences.review, defaultWorkspacePreferences().review);
});

test("parseStoredWorkspacePreferences clamps layout sizes", () => {
  const preferences = parseStoredWorkspacePreferences({
    layout: {
      sidebarWidth: 120,
      contentRailWidth: 900,
    },
  });

  assert.equal(preferences.layout.sidebarWidth, workspaceLayoutLimits.sidebarWidth.min);
  assert.equal(preferences.layout.contentRailWidth, workspaceLayoutLimits.contentRailWidth.max);
});

test("parseStoredWorkspacePreferences preserves review customization", () => {
  const preferences = parseStoredWorkspacePreferences({
    review: {
      questionStrategy: "custom",
      questionTypes: ["fillIn", "fillIn", "flashcards", "legacy"],
    },
  });

  assert.equal(preferences.review.questionStrategy, "custom");
  assert.deepEqual(preferences.review.questionTypes, ["fillIn", "flashcards"]);
});

test("parseStoredWorkspacePreferences preserves library clean mode", () => {
  const preferences = parseStoredWorkspacePreferences({
    isLibraryCleanMode: true,
  });

  assert.equal(preferences.isLibraryCleanMode, true);
});

test("parseStoredWorkspacePreferences preserves workspace pane layout preference", () => {
  const preferences = parseStoredWorkspacePreferences({
    workspacePaneLayoutPreference: "vertical",
  });

  assert.equal(preferences.workspacePaneLayoutPreference, "vertical");
});

test("parseStoredWorkspacePreferences preserves lookup reference tag visibility", () => {
  const preferences = parseStoredWorkspacePreferences({
    showLookupReferenceTags: true,
  });

  assert.equal(preferences.showLookupReferenceTags, true);
});
