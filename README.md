# Workspaces (iOS)

A prototype SwiftUI client for [workspaces.xyz](https://workspaces.xyz) — a weekly
showcase of desk and workspace setups. Browse the feed of issues, page through
photo galleries, read guest bios and Q&As, and explore the gear behind each setup.

## Features

- **Feed** — an infinite-scrolling list of setups (hero photo, issue number, guest,
  location, tags) with pull-to-refresh.
- **Detail** — a horizontally paged photo gallery, guest bio and links, gear grouped
  by category (tap items with affiliate links to open them), Q&A, and a share button
  linking to `https://workspaces.xyz/p/{slug}`.
- **Explore** — browse all tags as a chip cloud, filter the feed by tag, and search
  guests by name (GROQ `match`).

Dark-mode friendly, no third-party dependencies, async/await throughout.

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
├── WorkspacesApp.swift        # App entry, tab root
├── Models/Models.swift        # Setup, Tag, Photo, Gear, QA, PortableText decoder
├── Networking/SanityClient.swift  # GROQ URL building + envelope decoding
├── Stores/                    # @Observable stores (feed w/ pagination, detail, tags)
└── Views/                     # Feed, Detail, Explore + shared components
```

This is a prototype; there is no offline persistence beyond the URL/image caches.
