# Workspaces (iOS)

A prototype SwiftUI client for [workspaces.xyz](https://workspaces.xyz) — a weekly
showcase of desk and workspace setups. Browse the feed of issues, page through
photo galleries, read guest bios and Q&As, and explore the gear behind each setup.

## Features

The UI is deliberately editorial — serif display type, hairline rules, full-bleed
photography, and a magazine masthead instead of stock iOS chrome.

- **Latest** — the front-of-book feed: a full-bleed lead story, then entries
  alternating between full-width and split layouts (with oversized issue
  numerals), infinite scroll and pull-to-refresh.
- **Detail** — a feature spread: paged full-bleed gallery ("FIG. 1 / 6"), serif
  headline with kicker, guest bio and links, gear grouped by category (items with
  affiliate links open in Safari), Q&A, and a share button linking to
  `https://workspaces.xyz/p/{slug}`.
- **Index** — the back-of-book: a typographic two-column tag index, tag
  filtering, and guest-name search (GROQ `match`) with compact result rows.

Dark-mode friendly (paper white inverts to near-black), no third-party
dependencies, async/await throughout.

## Data source

The app reads from the public, **read-only** Sanity Content Lake dataset that
powers workspaces.xyz. No authentication or API key is required — the query
endpoint is the same one the public website uses:

```
https://ui5qde1a.apicdn.sanity.io/v2024-01-01/data/query/production?query=<GROQ>
```

Queries are plain [GROQ](https://www.sanity.io/docs/groq); responses arrive in a
`{"result": ...}` envelope. Portable Text fields (`guestBio`, `qa[].answer`) are
flattened to plain paragraphs by a tolerant decoder. Images are served from the
Sanity CDN with server-side resizing (`?w=<px>&auto=format&q=80`).

Please be considerate: this is someone else's public dataset. The app only issues
small, cached read queries.

## Requirements

- Xcode 16 or newer (the project uses file-system-synchronized groups)
- iOS 17.0+ deployment target

## Running

```sh
open Workspaces.xcodeproj
```

Select the **Workspaces** scheme and an iOS 17+ simulator, then Run. Or from the
command line:

```sh
xcodebuild -project Workspaces.xcodeproj -scheme Workspaces \
  -destination 'generic/platform=iOS Simulator' build
```

## Project layout

```
Workspaces/
├── WorkspacesApp.swift        # App entry, masthead + Latest/Index switcher
├── Models/Models.swift        # Setup, Tag, Photo, Gear, QA, PortableText decoder
├── Networking/SanityClient.swift  # GROQ URL building + envelope decoding
├── Stores/                    # @Observable stores (feed w/ pagination, detail, tags)
└── Views/                     # Feed, Detail, Index + typography/image components
```

This is a prototype; there is no offline persistence beyond the URL/image caches.
