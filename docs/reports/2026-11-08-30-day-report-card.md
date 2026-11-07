# Programming publications vs Hacker News and DEV: 30-day report card

Generated 8 Nov 2026. Sources: the six Medium publications' RSS feeds (read on device by Scout, see
`2026-11-08-publication-digest.md`), the Hacker News Algolia API, and the DEV (dev.to) public API.

## What "last 30 days" can mean for each source

| Source | What is available | 30-day view |
|---|---|---|
| Medium publications | RSS holds only the latest ~10 posts | **Not available from feeds.** Each feed covers 2 minutes to 3 days (Better Programming: its last 10 posts, Nov 2023). A 30-day view needs Scout to collect daily. |
| Hacker News | Full search by date (Algolia) | Available: submissions linking each publication, points |
| DEV (dev.to) | `top=30` articles API | Available: the 300 top articles of the last 30 days |

## Hacker News: do these publications still reach HN?

Submissions whose URL is the publication, by the Algolia search API.

| Publication | Last 30 days | Last 90 days | All time | Most recent HN submission |
|---|---|---|---|---|
| Level Up Coding (levelup.gitconnected.com) | 0 | 0 | 455 | 28 Aug 2025 |
| ITNEXT (itnext.io) | 0 | 0 | 589 | 3 Mar 2026 |
| Better Programming (betterprogramming.pub) | 0 | 0 | 542 | 11 Dec 2024 |
| JavaScript in Plain English | 0 | 0 | 5 | 25 Aug 2024 |
| Stackademic (blog.stackademic.com) | 0 | 0 | not checked | not checked |
| Data Science Collective | 2 (max 2 points) | 6 (max 17 points) | not checked | Nov 2026 |

For scale, HN had **1,300 stories with 100+ points** in the same 30 days, and **281 submissions of any medium.com URL**.

**Reading:** these publications used to reach HN hundreds of times; in the last 90 days only Data Science Collective did,
and with very few points.

## DEV (dev.to): the 300 top articles of the last 30 days

- **139 distinct writers**; the most prolific wrote 13 of the 300.
- Median **30 reactions** (max 229), median **15 comments**, median **7-minute** read.
- Top tags: ai (153), discuss (70), programming (60), webdev (56), opensource (54), devchallenge (51).
- Title shapes: **34% colon subtitles** (101 of 300), **2% listicles** (5 of 300). Level Up Coding's feed: 70% formula titles.
- Top three: “How to Become a Tech Conference Speaker…” (229), “Promise Delivered: Welcome to the DEV Hall of Fame…” (228),
  “Your Browser Can Do WHAT?! 5 AI Features That Actually Work…” (213).

## Report card

| | Medium publications (6) | Hacker News | DEV |
|---|---|---|---|
| Volume | ~10 posts per feed; ITNEXT and DSC ~3–4 a day | 1,300 stories ≥100 points in 30 days | 300 top articles in 30 days |
| Reach on HN | Near zero now (DSC: 2 submissions) | – | – |
| Formula titles | 20–70% (Level Up highest) | not measured | 34% colon, 2% listicle |
| Writer spread | 7–10 writers per 10 posts | not measured | 139 writers in 300 |
| Writing quality | Scout's rubric 2.42–2.92 of 3 on 1–5 readable posts each | not measured | not measured |
| Paywall | 43 of 60 feed posts member-only | – | open |

## Limits

- Medium figures are one snapshot of each feed, not 30 days. DEV and HN are 30-day windows.
- HN counts only submissions whose URL is on the publication's domain (or path, for Data Science Collective).
- DEV's `top=30` list is DEV's own ranking of its most-engaged articles, not every article published.
- Writing-quality scores exist only for Medium posts that Scout read on device; DEV and HN were not scored.
