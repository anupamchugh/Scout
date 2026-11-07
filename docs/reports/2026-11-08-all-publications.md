# All publications, read on device

Generated 8 Nov 2026 on this Mac with ScoutKit's `PublicationComparison`, the engine behind Scout's Compare tab. Each publication's current feed (about ten posts) was read by Apple's on-device model with one neutral `@Generable` rubric; the checker rejects any read whose quotes are not in the article. Every number, bucket and readability score is computed in code.

> These are small, recent samples. Member-only posts carry only a preview and are not judged. The rubric is not yet measured against an editor's decisions. Patterns, not verdicts.

## Writing and packaging

| Publication | Posts (dates) | Writers | Judged | Score /3 | Depth strong | Specific strong | Colon titles | Templated | Top writer | Stock /1k | Reframes /1k | Flesch | Words/sentence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Level Up Coding | 10 (6 Nov 2026) | 7 | 4 | 2.69 | 75% | 50% | 70% | 20% | 30% | 0.53 | 1.00 | 41 | 11 |
| Better Programming | 10 (10 Nov 2023) | 8 | 3 | 2.42 | 0% | 33% | 40% | 0% | 20% | 0.35 | 0.54 | 46 | 14 |
| ITNEXT | 10 (4 Nov 2026 – 6 Nov 2026) | 9 | 5 | 2.75 | 60% | 100% | 30% | 0% | 20% | 0.01 | 1.13 | 51 | 12 |
| JavaScript in Plain English | 10 (7 Nov 2026) | 9 | 1 | 2.75 | 0% | 0% | 0% | 0% | 20% | 0.00 | 1.62 | 57 | 11 |
| Stackademic | 10 (6 Nov 2026 – 7 Nov 2026) | 10 | 1 | 2.75 | 0% | 100% | 10% | 0% | 10% | 0.00 | 0.00 | 39 | 12 |
| Data Science Collective | 10 (3 Nov 2026 – 6 Nov 2026) | 9 | 3 | 2.92 | 67% | 100% | 10% | 0% | 20% | 0.12 | 1.23 | 57 | 11 |

Flesch reading ease: higher reads easier; 60–70 is plain English, 30–50 is typical technical writing.

## Good slop vs bad slop

Packaging × substance, decided in code. **Formula** = listicle, how-to or colon-subtitle title, or a title template the writer reuses. **Solid** = rubric score ≥ 2.5 of 3 and specificity not weak. **Good slop** = formula, solid. **Bad slop** = formula, thin.

| Publication | Plain and solid | Good slop | Bad slop | Plain but thin | Not judged |
|---|---|---|---|---|---|
| Level Up Coding | 0 | 3 | 0 | 1 | 6 |
| Better Programming | 1 | 1 | 0 | 1 | 7 |
| ITNEXT | 2 | 2 | 0 | 1 | 5 |
| JavaScript in Plain English | 1 | 0 | 0 | 0 | 9 |
| Stackademic | 1 | 0 | 0 | 0 | 9 |
| Data Science Collective | 2 | 1 | 0 | 0 | 7 |

### Level Up Coding

| Bucket | Score | Writer | Story | Most generic sentence (reader's pick, checked) | Reader's reason |
|---|---|---|---|---|---|
| Formula, solid (good slop) | 3.00 | Vlad Zoff | [Multi-Tenant RAG in Next.js: Relevance Is Not Authorization](https://levelup.gitconnected.com/multi-tenant-rag-in-next-js-relevance-is-not-authorization-4bfcfd30ca32) | “A practical pattern for tenant-scoped retrieval with PostgreSQL, pgvector, row-level security, and integration tests.” | The article details a concrete implementation with schema, code, and failure example tied to its own architecture. |
| Formula, solid (good slop) | 2.75 | Nagesh Singh Chauhan | [Caching in LLMs: The Layers That Make AI Systems Fast and Affordable](https://levelup.gitconnected.com/caching-in-llms-the-layers-that-make-ai-systems-fast-and-affordable-70a83a21688c) | “A guest messages a hotel support agent: “What time is check-in?” The agent retrieves the policy, assembles a prompt, calls the LLM and replies.” | The article details layered caching mechanisms with technical trade-offs but lacks deep system-level implementation examples. |
| Plain but thin | 2.50 | Nagesh Singh Chauhan | [Dynamic Time Warping(DTW) Algorithm in Time Series](https://levelup.gitconnected.com/dynamic-time-warping-dtw-algorithm-in-time-series-98d54b8141b2) | “The objective of time series comparison methods is to produce a distance metric between two input time series.” | The article focuses on DTW’s mathematical structure and constraints, but lacks concrete code or unique examples. |
| Formula, solid (good slop) | 2.50 | Kemal Aydın | [Pixels Have Stories: The Hidden World of Image Processing](https://levelup.gitconnected.com/pixels-have-stories-the-hidden-world-of-image-processing-6b63f4766a17) | “What do we really see when we look at a photograph?” | The article details specific filters, real-world pipelines, and measurable outputs beyond generic definitions. |

### Better Programming

| Bucket | Score | Writer | Story | Most generic sentence (reader's pick, checked) | Reader's reason |
|---|---|---|---|---|---|
| Formula, solid (good slop) | 2.75 | Ege Aytin | [WebAssembly with Go: Taking Web Apps to the Next Level](https://medium.com/better-programming/webassembly-with-go-taking-web-apps-to-the-next-level-8d81fccd8250) | “What does this playground do? Well, without diving too deep, its a interactive module of Permify which used for creating and testing authorization models.” | The article focuses on a specific Go-WASM integration for Permify’s Playground, with unique code examples and deployment steps not widely covered. |
| Plain and solid | 2.50 | Drew Althage | [Deploy CoreML Models on the Server with Vapor](https://medium.com/better-programming/deploy-coreml-models-on-the-server-with-vapor-48809a853fae) | “Apple provides a few pre-trained models, so today we’ll deploy an image classification model on the server behind a REST API with Vapor and create a SwiftUI client to consume it.” | The article focuses on a specific prototype using Vapor and CoreML for image classification, avoiding broad generalizations. |
| Plain but thin | 2.00 | Tony Stubblebine | [Let a thousand programming publications bloom.](https://medium.com/better-programming/let-a-thousand-programming-publications-bloom-bf37baef8f27) | “Medium has always had publications that acted as something in between a group blog and a sub-reddit.” | The article repeats common observations without unique technical examples or measurable outcomes. |

Flagged by the checker (not scored): GPT Function Calling: 5 Underrated Use Cases — generic sentence not found in the article.

### ITNEXT

| Bucket | Score | Writer | Story | Most generic sentence (reader's pick, checked) | Reader's reason |
|---|---|---|---|---|---|
| Plain and solid | 3.00 | Sebastian Daberdaku | [What ten months of deleting idle nodes taught us about Karpenter](https://itnext.io/what-ten-months-of-deleting-idle-nodes-taught-us-about-karpenter-df79f445b02d) | “Nodes deleted per day, averaged by month, across all our clusters. December covers 24 to 31 December.” | The article uses unique data from a specific deployment, custom code examples, and a bespoke tool to illustrate Karpenter’s limitations. |
| Formula, solid (good slop) | 3.00 | Filipe Motta | [Kubernetes Multi-Tenancy, Layer by Layer: Isolation Proved by Being Refused](https://itnext.io/kubernetes-multi-tenancy-layer-by-layer-isolation-proved-by-being-refused-cc2f92f41cfc) | “The Kubernetes documentation on multi-tenancy describes isolation with two words and then warns against taking them literally.” | The article uses a detailed lab with code, network policies, and layered isolation to prove isolation, focusing on concrete technical steps. |
| Formula, solid (good slop) | 2.75 | Hantsy | [Applying DDD with Jakarta EE: Strategic and Tactical Design with Jakarta Data](https://itnext.io/applying-ddd-with-jakarta-ee-strategic-and-tactical-design-with-jakarta-data-8618319ecda2) | “The example separates cataloging and lending because they model different concerns:” | The article builds a unique library system example with specific DDD patterns and code context. |
| Plain and solid | 2.75 | omrilotan | [Who’s Watching Production When the Agents Ship?](https://itnext.io/whos-watching-production-when-the-agents-ship-7636afdfed5f) | “More code reaches production now, less of it has been read line by line, and some of it ships without a human pressing the button.” | The article uses concrete examples like agent workflows, observability tools, and rollout strategies tied to its own context. |
| Plain but thin | 2.25 | Oliver Alonso | [Engineers Are Cannibalizing the Product Manager Role](https://itnext.io/engineers-are-cannibalizing-the-product-manager-role-ac7e4129933e) | “Teams are shrinking into pods, and most of them won’t need a PM of their own.” | The article uses a unique organizational diagram and specific examples like Coinbase and Netguru to illustrate structural shifts beyond generic trends. |

Flagged by the checker (not scored): 100% GPU Utilization, 39% of Rated FP16 — evidence quote not found in the article; reason contains a number · Persistent memory for AI coding agents: no prompt stuffing — evidence quote not found in the article · A Wardrobe Raid for Sparkle Emoji, an Oompa Loompa Shift for Every Ticket, and a Draw 25 Card… — evidence quote not found in the article.

### JavaScript in Plain English

| Bucket | Score | Writer | Story | Most generic sentence (reader's pick, checked) | Reader's reason |
|---|---|---|---|---|---|
| Plain and solid | 2.75 | Anna Parker / Business & Tech Analyst | [Debounce vs Throttle in JavaScript: Which One Do You Need?](https://javascript.plainenglish.io/debounce-vs-throttle-in-javascript-which-one-do-you-need-982625f7979f) | “Both limit how often a function runs. They solve different problems, and mixing them up leads to laggy or unresponsive interfaces.” | The article contrasts two techniques with code examples and real-world use cases, focusing on practical trade-offs rather than abstract theory. |

Flagged by the checker (not scored): How to embed an npm downloads badge on your website — evidence quote not found in the article.

### Stackademic

| Bucket | Score | Writer | Story | Most generic sentence (reader's pick, checked) | Reader's reason |
|---|---|---|---|---|---|
| Plain and solid | 2.75 | Renaldi Purwanto | [RAG in Go With PostgreSQL and pgvector](https://blog.stackademic.com/rag-in-go-with-postgresql-and-pgvector-ef36135f2a7e) | “Our internal documentation explained what should happen when transactions timed out, refunds were requested, or providers sent duplicate callbacks.” | The article details a unique Go-PostgreSQL-pgvector pipeline with code-first embedding and retrieval logic. |

Flagged by the checker (not scored): How Packet Sniffing Works — evidence quote not found in the article; generic sentence not found in the article.

### Data Science Collective

| Bucket | Score | Writer | Story | Most generic sentence (reader's pick, checked) | Reader's reason |
|---|---|---|---|---|---|
| Plain and solid | 3.00 | Paolo Perrone | [What is Agentic Search?](https://medium.com/data-science-collective/what-is-agentic-search-f6aa38d97c0b) | “Agentic search is a model searching in a loop: it writes a query, reads the results and picks its next move, whether that is another search, a page to open or the answer.” | The article builds a detailed loop with code, token counts, and benchmark data to illustrate cost and performance trade-offs. |
| Plain and solid | 3.00 | Benjamin Etienne | [Building an offline & private Personal Markdown Search Engine](https://medium.com/data-science-collective/building-an-offline-private-personal-markdown-search-engine-2e7e6f600989) | “PMS is a lightweight, local-first hybrid search engine and web clipper for personal Markdown knowledge bases, built in Python on top of SQLite (FTS5 + sqlite-vec) and ONNX (fastembed).” | The article details a unique technical stack and custom chunking logic not commonly found in similar tools. |
| Formula, solid (good slop) | 2.75 | Ananya B | [Survival Analysis in Python: What Your Churn Model Isn't Telling You](https://medium.com/data-science-collective/survival-analysis-in-python-what-your-churn-model-isnt-telling-you-2d920fa0bf1a) | “In the age of AI, we have increasingly sophisticated predictive analytics algorithms.” | The article uses a unique Python-based example with lifelines to illustrate survival analysis concepts beyond standard explanations. |

Flagged by the checker (not scored): Why DART wins your Optuna slice plot and loses the benchmark — evidence quote not found in the article.

## Method and limits

- One feed fetch per publication on the date above; Medium feeds hold about ten posts, so this is a snapshot.
- Better Programming stopped publishing in November 2023; its side is its last ten posts.
- Readability counts syllables with a simple rule, so Flesch scores are approximate; code blocks are excluded.
- “Slop” here names packaging and genericity patterns only. Whether a story is worth curating stays the editor's call.