# Shiken

試験 — a revision planner that holds you accountable.

Plan from exam dates and weighted topics, track what you actually study, and see the planned-vs-actual gap honestly each week.

- Native SwiftUI for macOS, iOS, and iPadOS (macOS 15+ / iOS 18+)
- SwiftData storage, CloudKit-safe schema (iCloud sync lands once an Apple Developer account is wired up)
- Pure, unit-tested planner engine — deterministic week-by-week scheduling from topic weights

## Build

Project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Shiken.xcodeproj -scheme "Shiken macOS" -destination 'platform=macOS' build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Shiken.xcodeproj -scheme "Shiken Tests" -destination 'platform=macOS' test
```

## Status

Pass 1 shipped: SwiftData models + `PlannerEngine` (9 unit tests green). In progress: subjects/topics + planner grid, focus timer + session log, planned-vs-actual review + Obsidian export.