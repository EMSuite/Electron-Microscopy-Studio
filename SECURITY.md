# Security

macEM is a desktop application that reads microscopy files you choose. It runs in the macOS App Sandbox and has no telemetry or
analytics. The App Store build connects to no other computer; the website download connects only to fetch its signed update
feed (Sparkle, mac4dstem.com), sending no system profile, and Check for Updates can be turned off in Settings. Its one listener is the agent door (Settings > Agents, off by default): on
this Mac's loopback address only, for an AI agent you run on the same Mac, and only requests carrying its token. It reads and writes only the files you pick; security-scoped
bookmarks let it reopen them.

To report a vulnerability (a crafted file that crashes the app or escapes the sandbox, or a problem in the
redistributed HDF5 libraries), use GitHub's private reporting: the repository's **Security** tab, then *Report a
vulnerability*. Please do not open a public issue for it. You will get a reply in the advisory thread; fixes ship as a
normal release and are noted in `CHANGELOG.md`.
