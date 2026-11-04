# ScoutKit

The scouting logic behind Scout, with no app, SwiftData or UI dependencies, so other apps can use
it. iOS 27 and macOS 27.

| Area | What's in it |
| --- | --- |
| Feeds | `FeedSource`, `FeedItem`, `RSSParser` (RSS 2.0 and Atom with one `XMLParser`), `FeedClient` (a capped, cancellable `TaskGroup`), `FeedCache` (an actor) |
| Scoring | `Matching` (writer and story scores, lanes surfacing, author unification), `TagCooccurrence`, `TextGuard`, `AuthorStats` / `stats(for:)`, `Taste` (learning from swipes) |
| Export | `IssueRenderer` (Markdown, HTML, llms.txt), `ShortlistRenderer` (Markdown, CSV) and `Transferable` export types |
| Packs | `RolePack` (built-in packs, `.scoutpack` import and export), `PackStore` |
| Intelligence | `Embedder` (`NLEmbedding` similarity), `ImageTaste` (Vision feature prints), `PitchFacts` |

Everything here is deterministic code. The language-model sessions, which only write sentences,
live in the app (`ScoutProfile`, `Writer`).

```bash
swift test
```

The tests run on macOS without a simulator. `Tests/ScoutKitTests/Fixtures` holds a dated snapshot of
a public Medium feed; remove it or get the owner's approval before publishing.
