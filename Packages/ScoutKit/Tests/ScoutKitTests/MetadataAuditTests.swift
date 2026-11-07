//
//  MetadataAuditTests.swift
//  ScoutKitTests
//

import Testing
@testable import ScoutKit

struct MetadataAuditTests {
    @Test func flagsTrendingTagsTheTextNeverMentions() {
        let audit = MetadataAudit.audit(
            title: "Postmortem story: Cloudflare’s .unwrap() outage",
            tags: ["software-development", "software-engineering", "artificial-intelligence", "rust", "coding"],
            subtitle: nil, articleText: "A panic in Rust took down the proxy when unwrap met a None value.")
        #expect(audit.tagCount == 5 && audit.atTagLimit)
        #expect(audit.trendingTagsUnmentioned == ["artificial-intelligence"])
        #expect(audit.tagsInTitle == 0)
        #expect(!audit.hasSubtitle)
    }

    @Test func aTrendingTagTheTextUsesIsFine() {
        let audit = MetadataAudit.audit(title: "Caching in an LLM: The Layers", tags: ["llm", "ai"], subtitle: nil,
                                        articleText: "The model reuses the KV cache for every agent turn.")
        #expect(audit.trendingTagsUnmentioned.isEmpty)
        #expect(audit.tagsInTitle == 1)
    }

    @Test func previewsWithoutTextAreNotFlagged() {
        let audit = MetadataAudit.audit(title: "Iterator Pattern in .NET C#", tags: ["programming", "dotnet"],
                                        subtitle: nil, articleText: nil)
        #expect(audit.trendingTagsUnmentioned.isEmpty)
    }

    @Test func genericSubtitlesAreNamed() {
        let generic = MetadataAudit.audit(title: "DTW", tags: [],
                                          subtitle: "The article contains an understanding of the DTW algorithm.", articleText: nil)
        let specific = MetadataAudit.audit(title: "Caching", tags: [],
                                           subtitle: "Understanding KV Cache, Prefix Caching, and Semantic Caching", articleText: nil)
        #expect(generic.genericSubtitle && !specific.genericSubtitle)
    }

    @Test func subtitleIsTheFirstHeading() {
        #expect(MetadataAudit.subtitle(fromMarkdown: "Intro line\n\n### Start with the tenant identity\n\nBody") == "Start with the tenant identity")
        #expect(MetadataAudit.subtitle(fromMarkdown: "No headings here.") == nil)
    }
}

struct TagFitTests {
    let article = "A panic in Rust took down the proxy when unwrap met a None value in production traffic."
    let tags = ["rust", "software-engineering", "artificial-intelligence"]

    @Test func supportedTagsMustBeThePostsOwnAndEvidenceMustExist() {
        let v = TagFit.verdict(tags: tags, supported: ["rust", "rust", "kubernetes"],
                               evidence: "A panic in Rust took down the proxy", articleText: article)
        #expect(v.status == .checked)
        #expect(v.supported == ["rust"])
        #expect(v.unsupported == ["software-engineering", "artificial-intelligence"])
    }

    @Test func inventedEvidenceIsFlagged() {
        let v = TagFit.verdict(tags: tags, supported: ["artificial-intelligence"],
                               evidence: "AI agents now run every proxy at Cloudflare", articleText: article)
        #expect(v.status == .flagged)
        #expect(v.problem == "evidence sentence not found in the article")
    }
}
