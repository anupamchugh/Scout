# Publication Pulse — spec

Status: proposed, 7 November 2026. Nothing here is implemented yet.

## Why

Editors ask "what is the state of programming publications?" Scout reads the same feeds that could answer it,
but a feed only carries its latest ~10 items (Level Up Coding's feed on 7 Nov 2026 held ten posts, all from 6 Nov),
so a single fetch describes one day, not a trend. Publication Pulse keeps the history Scout already stores and
turns it into a short, cited report.

## The idea in one picture

```swift
PulseView {
    Collect   // code: fetch each tracked publication feed, store every post once (StoredPost, unique guid)
    Count     // code: posts per week, tags, writers, new vs returning — the model never sees or writes numbers
    Write     // model: @Generable sections that quote real post titles, through tools that read the store
    Check     // code: every quoted title must exist, no digits or links in model text, else plain data + flag
    Export    // code: Markdown / HTML, like IssueRenderer
}
```

This is the rule Scout already follows (`Scoring/Matching.swift`, `Agents/IssueChecker.swift`): code decides every
number and order; the model only writes words about evidence it was given.

## Scope

In:

1. **Tracked publications.** A list of feed sources to follow, starting with Medium publications via
   `FeedSource.publication(slug)` (e.g. `gitconnected` for Level Up Coding, `better-programming`) and any site feed
   found by `FeedDiscovery`. Stored as a new `TrackedPublication` model (name, source, added date).
2. **Collection.** Each refresh stores new items as `StoredPost` (already de-duplicated by `guid`, already has
   `firstSeen`, `categories`, `authorKey`). Add `publication: String?` to `StoredPost` so a post records which tracked
   feed it came from (today `foundUnder` holds lane names, which is not the same thing).
   Collection runs when the app refreshes. On iOS, add a `BGAppRefreshTask` so collection continues when the app is
   closed; on macOS, refresh on launch and on a timer while running. Gaps are recorded, not hidden (see Coverage).
3. **Stats (ScoutKit, pure code, tested).** New `Scoring/PulseStats.swift` taking `[PostRecord]` and a date range:
   - posts per publication per ISO week;
   - top tags per publication, and tags whose share rose or fell most against the previous period;
   - distinct writers; writers new in this period; writers posting in more than one tracked publication;
   - coverage: first and last day with data per publication, and days with no successful fetch.
4. **Report writing (app, Foundation Models).** New `ScoutMode.pulse` and a `PulseReport` built from `@Generable`
   sections. Each section gets its numbers from code and asks the model only for wording:

   ```swift
   @Generable struct PulseTakeaway {
       @Guide(description: "A post title copied exactly from the tool results") var evidenceTitle: String
       @Guide(description: "One plain sentence about what changed, no numbers, no links") var sentence: String
   }
   ```

   Sections: headline, topic shifts (one takeaway per rising/falling tag), writers to watch, per-publication notes,
   and a fixed, code-written "Method and limits" section.
5. **Tools** (same shape as `RecentPostsTool` / `SearchSavedTool` in `Scout/Intelligence/ScoutProfile.swift`):
   - `PublicationPostsTool(publication, week)` — titles and snippets of stored posts;
   - `TagPostsTool(tag, period)` — stored posts carrying a tag;
   - existing `SearchSavedTool` for free-text lookups.
   Tools return stored text only. They never return computed scores.
6. **Checking.** Extend `IssueChecker` (or a sibling `PulseChecker`) so every `evidenceTitle` matches a stored post
   in the report's range and publication, and model text has no digits or links. Failures are replaced with the
   code-written fact (e.g. the tag name and its counts) and flagged in the UI.
7. **Report screen and export.** A Pulse view listing tracked publications, coverage, the stats tables, and the
   written sections. Export to Markdown and HTML through a `PulseRenderer` modelled on `Export/IssueRenderer.swift`.
8. **Evaluations.** Add Pulse cases to `Tests/ScoutEvaluations.swift`: quoted titles exist, sentences contain no
   numbers, takeaway direction matches the code's rise/fall.

Out (for now): scraping Medium beyond public RSS; per-post read counts or claps (not in RSS); judging article
quality; sending the report anywhere automatically; Private Cloud Compute (revisit only if on-device context is too
small for a month of titles — see Open questions).

## Scouting the publications' writers and stories

The same stored posts feed Scout's existing deck, so tracked publications also become a source of writers and
stories to approach, not only a report.

- **Ranking stays in code.** Each tracked publication is passed to the existing `Matching.candidates` (writers) and
  `Matching.stories` (stories) as a `LaneSpec`, with its name, its top tags from `PulseStats`, and a theme. Writer
  numbers come from `AuthorStats` (posts per week, title patterns), as today. The deck, shortlist and outreach
  notes work unchanged.
- **Cross-publication writers.** `PulseStats` lists writers who post in two or more tracked publications; the
  writer card shows that list (plain data, no model text).
- **Choices fixed at runtime with `DynamicGenerationSchema`.** Use the pattern the Curator already uses in
  `Scout/Intelligence/IssueAgents.swift` (`.anyOf(lanes)`, `.anyOf(ids)`): when the model picks something, the
  schema only allows values that exist in the store right now, so it cannot produce an unknown ID through
  constrained sampling. For Pulse:

  ```swift
  // Built per report from code-ranked data; values unknown at compile time.
  let pick = DynamicGenerationSchema(name: "WriterToWatch", properties: [
      .init(name: "authorKey", schema: DynamicGenerationSchema(type: String.self, guides: [.anyOf(rankedAuthorKeys)])),
      .init(name: "evidenceGuid", schema: DynamicGenerationSchema(type: String.self, guides: [.anyOf(theirPostGuids)])),
      .init(name: "sentence", schema: DynamicGenerationSchema(type: String.self, guides: [])),
  ])
  let topicShift = DynamicGenerationSchema(name: "TopicShift", properties: [
      .init(name: "tag", schema: DynamicGenerationSchema(type: String.self, guides: [.anyOf(changedTags)])),
      .init(name: "evidenceGuid", schema: DynamicGenerationSchema(type: String.self, guides: [.anyOf(postsWithThoseTags)])),
      .init(name: "sentence", schema: DynamicGenerationSchema(type: String.self, guides: [])),
  ])
  ```

  Read results with `GeneratedContent.value(_:forProperty:)`. `rankedAuthorKeys` is the top of the code ranking
  (e.g. 10), so the model chooses *which* to feature and writes the sentence; it never ranks. Fixed-shape sections
  (headline, method) stay static `@Generable` types. The checker still runs: `anyOf` guarantees the ID exists,
  not that the pairing of writer and post is right, so the checker confirms `evidenceGuid` belongs to `authorKey`
  (or to `tag`).
- **Order of properties.** The model generates properties in declaration order, so evidence comes before the
  sentence, and the sentence is written about the chosen post.

## Coverage and honesty rules

- The report always shows its date range, the number of posts it is based on, and per-publication coverage.
- Under 14 days of data for a publication: that publication shows counts only, with "not enough history yet",
  and the model writes no trend sentence for it.
- A missed fetch day is shown as a gap. Feeds hold ~10 items, so a busy publication can lose posts if Scout does not
  refresh for a day or more; the report says so instead of implying completeness.
- Topic counts come from RSS `category` tags as the publication applied them, not from model classification.

## Acceptance criteria

1. With the debug demo data, adding Level Up Coding and Better Programming as tracked publications and refreshing
   stores posts with `publication` set, and refreshing again adds no duplicates.
2. `PulseStats` unit tests in `Packages/ScoutKit` cover weekly counts, rising/falling tags, new vs returning writers,
   cross-publication writers, and coverage gaps (`swift test` passes).
3. A generated report on Apple Intelligence hardware shows only titles that exist in the store; a scripted test with
   `ScriptedLanguageModel` proves an invented title is replaced and flagged.
4. A publication with under 14 days of data gets no model-written trend sentence.
5. Markdown and HTML exports contain the date range, post count, coverage and Method and limits section.
6. Pulse cases run in the Evaluations suite.
7. Tracked publications appear as lanes in the deck; a writer posting in two tracked publications shows both.
8. "Writers to watch" and "Topic shifts" use `DynamicGenerationSchema` with `anyOf` from the store, and a scripted
   test shows a mismatched writer/post pair is caught by the checker.

## Build order

1. `publication` field + `TrackedPublication` model + collection (and BG refresh on iOS). Start collecting early;
   the report is only useful after two to four weeks.
2. `PulseStats` with tests.
3. Pulse screen with code-only tables (useful even before any model text).
4. `ScoutMode.pulse`, tools, `@Generable` sections, checker.
5. Export and Evaluations.

## Apple sample code to borrow from

- *Generate dynamic game content with guided generation and tools* — building content from `@Generable` parts fed by tools.
- *Adding intelligent app features with generative models* — guided generation, tool calling, streaming sections.
- *Searching indexed content with natural language* (Core Spotlight) — later: ask questions over stored posts.
- *Book Tracker: Using Evaluations to evaluate an intelligent feature* — eval structure for step 5.
- *Generating Swift data structures with guided generation* — `@Generable`/`@Guide` for fixed sections and
  `DynamicGenerationSchema` → `GenerationSchema` → `GeneratedContent` for runtime choices.

## Open questions

1. Which publications go in the default list for the engineering pack?
2. Should `StoredPost` rows from tracked publications be kept forever, or pruned after a set period (e.g. 180 days)?
3. If a month of titles exceeds the on-device context, summarise per week first (code-chunked) or offer Private
   Cloud Compute as an opt-in?
