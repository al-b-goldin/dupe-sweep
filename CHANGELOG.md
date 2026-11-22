# Changelog

## 1.1 (2026-11-22)
- Fixed: the results screen showed only the first copy's file name. Copies with different names in one folder looked like one file (reported by a user, JMT_145.png and JMT_145a.png). Each row now shows its own file name above its folder, and the heading names every file in the set.
- The line under each set now says "same contents" and, when the names differ, how many names there are.
- New size options: ignore files smaller than 50 MB, 100 MB or 1 GB. A large-files-only scan reads far less.
- New check: a test fails if two copies in a set look the same on the results screen, or if the heading leaves out a name.
- The results screen now names what the scan left out: protected folders (for example `/System` or `~/Library`) and items it could not read. Before, the note was set but never shown.
- A scan that read no file says "Nothing was checked" and why, in place of "No duplicates found".
- "Put Everything Back" now counts the files it could not put back.
- If every extra copy changed after the scan, the last screen says "No files were moved" and offers "Scan Again".
- Clearer hint under the count: open a set, then click "Keep this one".
- Tests moved from XCTest to Swift Testing, so they run on a Mac without Xcode (`./scripts/test.sh`). New workflow tests for the app in `Tests/DupeSweepTests`.

## 1.0 (2026-11-12)
- Scan engine: size grouping, partial fingerprint, full SHA-256, APFS clone and hard link awareness.
- Keep rules: Smart, larger folder, most recent folder, oldest folder, newest file, oldest file, top of list. Pinned folders.
- Safe Trash mover with a recheck before each move and "Put Everything Back".
- SwiftUI app with drag and drop, progress, review list, light and dark mode.
- Universal build (Apple silicon and Intel) for macOS 14 and later.
