# Mac App Store listing: Electron Microscopy Studio (macEM)

The store build is named Electron Microscopy Studio (menu bar: Microscopy Studio) since 16 Nov 2026: App Review refuses "Mac" in an app name (guideline 5.2.5, macEM#743). The website build, Sparkle, GitHub and the bundle identifier keep macEM / `com.mac4dstem.macTEM`. The name comes from `MACEM_APP_NAME_YES` and `MACEM_MENU_NAME_YES` in `Config/Version.xcconfig`.

Drafts for Paul's approval, kept current with the app; the name, the subtitle and the screenshots are his.

One plain UTF-8 file per App Store Connect field. Counts are characters (`wc -m` in a UTF-8 locale), no trailing newline in the limited fields.

- `name.txt`: 26 / 30
- `subtitle.txt`: 28 / 30
- `promotional-text.txt`: 162 / 170
- `description.txt`: 3997 / 4000 (plain text, no markdown)
- `keywords.txt`: 90 / 100 (comma-separated, no spaces after commas; no word from the name or subtitle, which Apple indexes already, and no other product names; `tools/check-store-keywords.sh` enforces it in the inventory job)
- `whats-new.txt`: 954 / 4000 (2.6.0)
- `category.txt`: primary Education, secondary Productivity (no limit)
- `urls.txt`: support, marketing and privacy policy URLs on mac4dstem.com (no limit)
- `age-rating.txt`: questionnaire answers, all None, rating 4+ (no limit)
- `app-privacy.txt`: Data Not Collected; macEM's one outgoing connection is the person's own Materials Project search and download (#778); its one listener is the agent door on 127.0.0.1 (no limit)
- `review-notes.txt`: 3984 / 4000; walks a reviewer through every room with Help > Open Demo Data

Every claim comes from the README and the app's code as of 2026-11-10; nothing from the roadmap. Every signed build is
sandboxed. The formats read with a file of the same name beside them (EDAX .spd with its .spc and .ipr, EDAX .lsd with
its .spc and .csv, EDAX .up1 and .up2 with their .ang, Oxford .ebsp with its .ctf) get that file through the related-item
grant (`RelatedFileAccess`, macTEM#395); open one of each in the signed store build before a submission. An EDAX map's
.ipr is reached only under the map's own name: one named after the map's electron image (the .spd header's `fName`) is
not, and the map then opens without a pixel size (scale 1, no unit) and without saying why (read from the code, not yet
seen in a signed build, macTEM#102). The texts leave out NORDIF Pattern.dat, which asks for its folder once (macTEM#403)
and has not been opened in a signed build yet, and JEOL .asw, whose other files the sandboxed app is not given.
