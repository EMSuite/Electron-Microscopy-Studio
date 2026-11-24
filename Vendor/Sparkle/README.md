# Sparkle with the app-name rename

The website download of Electron Microscopy Studio updates itself with [Sparkle](https://github.com/sparkle-project/Sparkle)
(#583). Until 2.1.1 the app was macEM.app; a fresh download is now `Electron Microscopy Studio.app`, but stock Sparkle installs
an update in place, so a copy updated from an old release keeps the old file name (#759, #761).

Sparkle has a build setting for this, `SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME` (`Configurations/ConfigCommon.xcconfig`,
0 upstream). Built with 1, its installer moves the updated app to `<SUBundleName>.app`; the app's `SUBundleName` is
"Electron Microscopy Studio" (`macTEM/Info-Direct.plist`). The installer that runs an update is the installed app's own, so the
first release that carries this build renames nothing; every update after it renames the file. The bundle identifier, the
feed and the user's settings stay as they are.

## What is here

- `Sparkle.xcframework`: Sparkle at the tag and commit in `tools/lib/sparkle-pin.sh`, built by `tools/build-sparkle.sh` with
  that one setting changed, without dSYMs, signed ad hoc. Xcode signs the framework when it embeds it; `tools/release.sh`
  checks the download carries this build (the helpers' Mach-O UUIDs) and signs each helper with the Developer ID.
- `build-info.txt`: the tag, the commit, the setting, the Xcode, the workflow run that built it, and the SHA-256 of every file
  in the framework. `tools/run-tests.sh inventory` checks it against the tree, the pin and NOTICE.
- `Package.swift`: a local package whose one product, `Sparkle`, the Xcode project links in place of the remote package.

`tools/appcast.sh` signs the DMG with `sign_update` from the same tag's official Swift Package Manager zip (checksum in the pin).

## Rebuild (a new Sparkle tag)

1. Change `tools/lib/sparkle-pin.sh` (tag, commit, and the zip checksum from Sparkle's `Package.swift` at that tag) and NOTICE's
   tag and commit, and push the branch. `.github/workflows/sparkle.yml` builds it on GitHub's macOS runner and, since the pin
   is new, commits `Sparkle.xcframework` and `build-info.txt` here on that branch, with the run's URL in the message.
2. Pull that commit and open the pull request as usual.

`tools/build-sparkle.sh` runs on a Mac with Xcode too; its `build-info.txt` then says "built locally".

## Going back to stock Sparkle

Sparkle's note on the setting: turn it off once the rename is done. When the releases that rename have been out long enough
(an issue tracks it), point the project back at `https://github.com/sparkle-project/Sparkle` (up to next major from the tag),
delete this folder, `tools/build-sparkle.sh`, `tools/lib/sparkle-pin.sh` and `.github/workflows/sparkle.yml`, take
`sign_update` from `build/SourcePackages/artifacts/sparkle/Sparkle/bin` again in `tools/appcast.sh`, and drop the Sparkle
section of `tools/run-tests.sh inventory`.
