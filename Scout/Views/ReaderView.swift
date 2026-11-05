//
//  ReaderView.swift
//  Scout
//
//  The whole article, rendered natively from Markdown (ScoutKit's ReaderDocument) with Swift code
//  highlighted by ScoutKit's tokenizer. Full text appears only here, as in an RSS reader; exports carry
//  titles, links and short notes.
//

#if canImport(SafariServices) && os(iOS)
import SafariServices
#endif
import ScoutKit
import SwiftData
import SwiftUI

/// Swift highlighting from ScoutKit's tokenizer, in two palettes; the font comes from SwiftUI so Dynamic Type applies.
enum CodeHighlighter {
    static func highlight(_ code: String, language: String, dark: Bool) -> AttributedString {
        guard language == "swift" else { return AttributedString(code) }
        var result = AttributedString()
        for token in SwiftTokenizer.tokens(code) {
            var part = AttributedString(token.text)
            if let color = color(token.kind, dark: dark) { part.foregroundColor = color }
            result += part
        }
        return result
    }

    static func color(_ kind: SwiftTokenizer.Kind, dark: Bool) -> Color? {
        let hex: UInt32? = switch kind {
        case .keyword: dark ? 0xFF7AB2 : 0xAD3DA4
        case .type: dark ? 0x6BDFFF : 0x3900A0
        case .string: dark ? 0xFF8170 : 0xC41A16
        case .number: dark ? 0xD9C97C : 0x1C00CF
        case .comment: dark ? 0x7F8C98 : 0x5D6C79
        case .attribute: dark ? 0xFFA14F : 0x643820
        case .plain: nil
        }
        return hex.map { Color(light: $0, dark: $0) }
    }
}

struct ReaderView: View {
    let guid: String
    /// What the Ask sheet is about when opened from the reader.
    var askSubject: AskSubject?
    @State private var asking: AskSubject?
    @Environment(ScoutModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    #if os(macOS)
    @Environment(\.openURL) private var openURL
    #endif
    @Query private var posts: [StoredPost]
    @State private var markdown: String?
    @State private var loading = true
    @State private var showsSafari = false

    init(guid: String, askSubject: AskSubject? = nil) {
        self.guid = guid
        self.askSubject = askSubject
        _posts = Query(filter: #Predicate<StoredPost> { $0.guid == guid })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let post = posts.first {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(post.title).font(.title.bold()).foregroundStyle(Color.ink)
                        HStack(spacing: 8) {
                            Avatar(name: post.authorName, url: model.avatars[post.authorKey], size: 32)
                            Text(post.handle.map { "\(post.authorName) · @\($0)" } ?? post.authorName).font(.subheadline.weight(.medium))
                            Spacer()
                            if let minutes = post.readingMinutes { Text("\(minutes) min read").font(.caption).foregroundStyle(Color.inkSecondary) }
                        }
                        Divider()
                        if let markdown {
                            ForEach(Array(ReaderDocument.blocks(markdown).enumerated()), id: \.offset) { _, block in blockView(block) }
                            if HTMLToMarkdown.isPreview(markdown) {
                                readOnMedium("This feed only carries a preview. Read the rest on Medium.")
                            }
                        } else if loading {
                            HStack { ProgressView(); Text("Fetching the article from the writer's feed…").foregroundStyle(Color.inkSecondary) }
                        } else {
                            readOnMedium("This feed doesn't carry the full text.")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            }
            .background(Color.paper)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if let askSubject { ToolbarItem { AskButton { asking = askSubject } } }
            }
            .sheet(item: $asking) { AskSheet(subject: $0) }
            #if os(iOS)
            .sheet(isPresented: $showsSafari) {
                if let url = posts.first.flatMap({ URL(string: $0.link) }) { ReaderSafari(url: url).ignoresSafeArea() }
            }
            #else
            .onChange(of: showsSafari) { _, shows in
                // The Mac has no in-app Safari view: open the post in the default browser.
                guard shows else { return }
                showsSafari = false
                if let url = posts.first.flatMap({ URL(string: $0.link) }) { openURL(url) }
            }
            #endif
            .task {
                markdown = await model.article(for: guid)
                loading = false
            }
        }
    }

    private func readOnMedium(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).font(.callout).foregroundStyle(Color.inkSecondary)
            Button("Open in Reader", systemImage: "book") { showsSafari = true }.buttonStyle(.borderedProminent)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func blockView(_ block: ReaderBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text).font(level <= 2 ? .title2.bold() : level == 3 ? .title3.bold() : .headline).padding(.top, 6)
        case .paragraph(let text):
            Text(text).font(.body).foregroundStyle(Color.ink).tint(.scoutBlue)
        case .item(let depth, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker).monospacedDigit().foregroundStyle(Color.inkSecondary)
                Text(text).tint(.scoutBlue)
            }
            .padding(.leading, CGFloat(depth) * 18)
        case .quote(let text):
            Text(text).italic().foregroundStyle(Color.inkSecondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(Color.scoutGreen).frame(width: 3) }
        case .image(let url, let alt):
            AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { Rectangle().fill(Color.card).frame(height: 160) }
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityLabel(alt.isEmpty ? "Image from the article" : alt)
        case .code(let language, let code):
            CodeBlockView(code: code, language: language, dark: colorScheme == .dark)
        case .rule:
            Divider()
        }
    }
}

struct CodeBlockView: View {
    let code: String
    let language: String
    let dark: Bool
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MonoLabel(language.isEmpty ? "code" : language)
                Spacer()
                Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    Pasteboard.copy(code)
                    copied = true
                }
                .font(.caption)
                .accessibilityIdentifier("reader.copyCode")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(CodeHighlighter.highlight(code, language: language, dark: dark))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(dark ? Color(white: 0.1) : Color(white: 0.96), in: .rect(cornerRadius: 12))
        .accessibilityIdentifier("reader.code")
    }
}

#if os(iOS)
/// Fallback when no feed carries the full text: Safari's own Reader.
struct ReaderSafari: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = true
        return SFSafariViewController(url: url, configuration: configuration)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
