# Shiken (試験)

A revision planner that holds you accountable — plan from your exam date, focus-track the work you actually do, and confront the planned-vs-actual gap honestly every week.

Native SwiftUI for macOS, iOS, and iPadOS (macOS 15+ / iOS 18+). Local-first [SwiftData](https://developer.apple.com/documentation/swiftdata) storage with a CloudKit-safe schema — iCloud sync lands once an Apple Developer account is wired up.

## Features

- **Plan from your exam date** — set a daily study target (15–240 min) and Shiken builds a week-by-week plan back from the exam day, ending on "Exam week".
- **Manage subjects from the sidebar** — right-click any subject to rename it or delete it (topics, plans, and sessions go with it).
- **Priority dials, not fixed splits** — every topic gets an independent 1–100 priority dial. Dials are relative: drag any topic and the whole week re-allocates to exactly your daily target, no fiddly manual arithmetic.
- **Weekly and Daily views** — flip between the full week grid (tap a cell to mark it done) and the current week expanded day-by-day, with today highlighted.
- **Interruption-aware focus timer** — 25/50/90-minute sessions — or type any custom length (1–240 min) — that track time away from the app, so "my session was interrupted" stops being an excuse. Every session lands in the log.
- **Honest weekly review** — planned vs actual for the last 7 days, a planning grade for the week, and a one-page weekly letter you can export to Obsidian via the system share sheet.
- **Settings** — pick default focus length and daily target, and choose whether away-time tracking is on.

## How to use

1. **Add a subject.** Sidebar → *+* → name it (e.g. "Chemistry"), pick the exam date, set your daily target. Pick an accent colour if you like. **Right-click a subject** in the sidebar any time to rename or delete it.
2. **Add topics and weight the mix.** In the subject's Topics panel, rename topics ("Organic Chem", "Equilibria", …). Drag the priority dials to give each topic more or less of the week — the effective % readout and the "≈ 42m/wk" hint update live. The weekly plan builds itself.
3. **Read the plan.** *Weekly* shows every week from now to the exam (leftmost is "This Week", rightmost "Exam"); each cell is that topic's planned minutes for the week. Tap a cell to cross it off. *Daily* shows the current week one day at a time, today highlighted.
4. **Do the work.** *Focus* → pick subject + topic, choose 25/50/90 min or type any custom length (1–240 min), Start. If you tab away mid-session, away-time is tracked (or not, per Settings). Finished sessions appear under *Sessions*.
5. **Review weekly.** *Review* shows the gap: what you planned vs what you actually logged over the last 7 days, plus a grade and a weekly letter. Use **Export** to drop the letter into Obsidian (markdown + frontmatter).

## Build

Project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Shiken.xcodeproj -scheme "Shiken macOS" -destination 'platform=macOS' build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Shiken.xcodeproj -scheme "Shiken Tests" -destination 'platform=macOS' test
```

## Status

MVP complete: subjects/topics + priority-dial planner (weekly + daily), focus timer + session log (incl. custom lengths), planned-vs-actual review + Obsidian export, subject rename/delete, settings, generated app icon — 19 unit tests green across the planner and review engines. Next: physical-device iOS pass, then CloudKit sync once a Developer Account exists.