# Contributing

Thank you for helping. Bug reports, ideas and pull requests are welcome.

## Report a bug
Open an issue with the template. Include your macOS version, the Dupe Sweep version, what you did, and what you expected. Do not attach files from your Mac unless you are happy for them to be public.

## Send a change
1. Fork the repo and make a branch.
2. Run `swift test`. All tests must pass.
3. Add a test in `Tests/DupeEngineTests` for any change to the engine.
4. Run `swift build -c release && .build/release/DupeSweep --selftest`.
5. Open a pull request. Say what changed and why.

## Rules that protect users
- Files only ever go to the Trash. A change must never delete a file for good.
- A change must keep at least one copy of every duplicate set.
- No network calls and no telemetry.
- Keep the engine (`Sources/DupeEngine`) free of interface code.

## Style
Plain Swift. Small functions. Comments explain why, not what.
