//
//  MacIssueViews.swift
//  Scout (macOS)
//
//  The issue editor beside a live preview, with Markdown and HTML saved to disk. Rendering is
//  ScoutKit's IssueRenderer, the same code the iPhone app shares from.
//

import ScoutKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The next issue's editor (newsletter agents included), in its own navigation stack.
struct MacIssueColumn: View {
    @Query(sort: \IssueDraft.created, order: .reverse) private var issues: [IssueDraft]

    var body: some View {
        NavigationStack {
            if let issue = issues.first {
                IssueEditorView(issue: issue)
            } else {
                ContentUnavailableView("No issue yet", systemImage: "newspaper")
            }
        }
    }
}

struct MacIssuePreview: View {
    enum Format: String, CaseIterable, Identifiable {
        case preview = "Preview"
        case markdown = "Markdown"
        case html = "HTML"
        var id: String { rawValue }
        var title: LocalizedStringResource {
            switch self {
            case .preview: "Preview"
            case .markdown: "Markdown"
            case .html: "HTML"
            }
        }
    }

    @Query(sort: \IssueDraft.created, order: .reverse) private var issues: [IssueDraft]
    @State private var format = Format.preview
    @State private var exporting: TextFile?
    @State private var copied = false

    private var content: IssueContent? { issues.first?.content }

    var body: some View {
        NavigationStack {
            Group {
                if let content {
                    ScrollView {
                        switch format {
                        case .preview: rendered(content)
                        case .markdown: source(IssueRenderer.markdown(content))
                        case .html: source(IssueRenderer.html(content))
                        }
                    }
                } else {
                    ContentUnavailableView("No issue yet", systemImage: "newspaper")
                }
            }
            .background(Color.paper)
            .navigationTitle("Preview")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Format", selection: $format) {
                        ForEach(Format.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem {
                    Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        guard let content else { return }
                        Pasteboard.copy(format == .html ? IssueRenderer.html(content) : IssueRenderer.markdown(content))
                        copied = true
                    }
                    .help(format == .html ? "Copy HTML" : "Copy Markdown")
                    .disabled(content == nil)
                }
                ToolbarItem {
                    Menu("Save", systemImage: "square.and.arrow.down") {
                        Button("Save Markdown…") { save(.markdown) }
                        Button("Save HTML…") { save(.html) }
                        Button("Save llms.txt…") { save(nil) }
                    }
                    .help("Save the issue to a file")
                    .disabled(content == nil)
                }
            }
            .onChange(of: format) { copied = false }
            .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                          document: exporting, contentType: exporting?.type ?? .plainText,
                          defaultFilename: exporting?.name) { _ in exporting = nil }
        }
    }

    /// Saves the chosen format; nil saves llms.txt.
    private func save(_ format: Format?) {
        guard let content else { return }
        exporting = switch format {
        case .html: TextFile(text: IssueRenderer.html(content), type: .html, name: "issue-\(content.number).html")
        case .markdown, .preview: TextFile(text: IssueRenderer.markdown(content), type: TextFile.markdown, name: "issue-\(content.number).md")
        case nil: TextFile(text: IssueRenderer.llmsTxt(content), type: .plainText, name: "llms.txt")
        }
    }

    private func rendered(_ content: IssueContent) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: content.heading).font(.title.bold())
            if !content.intro.isEmpty { Text(verbatim: content.intro).font(.title3) }
            ForEach(content.sections, id: \.name) { section in
                if !section.name.isEmpty { MonoLabel(section.name).padding(.top, 6) }
                ForEach(Array(section.entries.enumerated()), id: \.offset) { _, entry in
                    Text(line(entry, number: content.number)).tint(.scoutBlue)
                }
            }
            if let spotlight = content.spotlight {
                Divider()
                Text(verbatim: IssueRenderer.markdown(IssueContent(number: content.number, title: content.title, intro: "",
                                                                   entries: [], spotlight: spotlight)))
                    .font(.callout)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: 640, alignment: .leading)
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func source(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.callout.monospaced())
            .textSelection(.enabled)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: .rect(cornerRadius: 12))
            .padding(20)
    }

    /// One entry as the Markdown bullet IssueRenderer writes, parsed so its link is clickable.
    private func line(_ entry: IssueContent.Entry, number: Int) -> AttributedString {
        let single = IssueContent(number: number, title: "", intro: "", entries: [entry])
        let markdown = IssueRenderer.markdown(single).split(separator: "\n").last.map(String.init) ?? entry.title
        return (try? AttributedString(markdown: "•" + markdown.dropFirst())) ?? AttributedString(entry.title)
    }
}

/// A text file for the save panel.
struct TextFile: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]
    static let markdown = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    static let writableContentTypes: [UTType] = [.plainText, markdown, .html]

    var text: String
    var type: UTType
    var name: String

    init(text: String, type: UTType, name: String) {
        self.text = text
        self.type = type
        self.name = name
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
        type = .plainText
        name = "Untitled"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
