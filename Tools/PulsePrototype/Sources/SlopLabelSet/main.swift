//  SlopLabelSet — snapshots every preset publication's readable feed articles into an editor label set, so the
//  on-device slop rubric can be measured against a person. Existing ratings are never changed.
//
//  swift run SlopLabelSet [label-set folder]
//  (default: ~/Desktop/workspace/WritingCorpus/runs/slop-labels, or $SCOUT_WRITING_CORPUS/runs/slop-labels)
//
//  Then open labels.json and set clarity, depth, evidence, originality and specificity to strong, adequate or weak
//  for each article you have read. The ScoutKit test SlopRubricEvaluation compares the model with those ratings.

import Foundation
import ScoutKit

let corpus = ProcessInfo.processInfo.environment["SCOUT_WRITING_CORPUS"]
    ?? NSString("~/Desktop/workspace/WritingCorpus").expandingTildeInPath
let folder = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : corpus + "/runs/slop-labels")
let articles = folder.appending(path: "articles")
let labelsFile = folder.appending(path: "labels.json")
try FileManager.default.createDirectory(at: articles, withIntermediateDirectories: true)

let existing = (try? SlopLabels.load(labelsFile)) ?? []
let client = FeedClient(maxConcurrent: 2)
var added: [SlopLabel] = []
for choice in PublicationChoice.presets {
    do {
        let items = try await client.fetch(choice.source)
        var kept = 0
        for item in items {
            guard let html = item.contentHTML else { continue }
            let markdown = HTMLToMarkdown.convert(html)
            guard !HTMLToMarkdown.isPreview(markdown) else { continue }
            let id = item.canonicalLink.lastPathComponent
            let file = "articles/\(id).md"
            if !existing.contains(where: { $0.id == id }) {
                try markdown.write(to: folder.appending(path: file), atomically: true, encoding: .utf8)
            }
            added.append(SlopLabel(id: id, publication: choice.name, title: item.title,
                                   link: item.canonicalLink.absoluteString, article: file))
            kept += 1
        }
        print("\(choice.name): \(kept) readable of \(items.count)")
    } catch {
        print("FAILED \(choice.name): \(error)")
    }
}
let merged = SlopLabels.merge(existing, adding: added)
try SlopLabels.save(merged, to: labelsFile)
let rated = merged.filter { $0.editor.critique != nil }.count
print("\(merged.count) articles in \(labelsFile.path()) (\(merged.count - existing.count) new, \(rated) fully rated)")
