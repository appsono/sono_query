# Changelog

## 0.8.2

- Restore flutter constraint dropped in db85454; without it
  SonoQueryDesktop never registered on Linux/Windows (desktop
  dart-plugin self-impl requires flutter >=2.11.0)

## 0.8.1

- Fix crash on Linux/Windows startup scan: MissingPluginException
  now returns null instead of propagating

## 0.8.0

- All heavy Android plugin work (MediaStore scans, cover decode/encode,
  tag-edit file copies) now runs on a small background thread pool
  instead of the platform main thread, removing per-cover and per-scan
  UI stalls. Results are delivered back on the main thread
- `getCoverThumbnail()` falls back to a subsampled native decode of the
  embedded tag picture when MediaStore has no thumbnail (pre-Q devices
  and files MediaStore does not index). Two-pass decode with
  `inSampleSize` bounds peak bitmap memory to ~4MB regardless of
  source art resolution; bitmaps are explicitly recycled
- Thumbnail-sized embedded pictures under 300KB are returned as-is
  with zero decode cost

## 0.7.1

- readCover ran its synchronous tag parse on the calling isolate,
  blocking the UI during list scrolls; the parse now runs via Isolate.run

## 0.7.0

- Adds incremental scanning: `getSongsStream()` accepts `knownFingerprints`
  (path to `mtimeMs:size` map) and an `onUnchanged` callback. On desktop/iOS,
  files whose fingerprint matches are skipped entirely instead of having
  their tags re-read, turning warm rescans into a stat sweep. Stat
  partitioning runs in a background isolate
- Adds `mtimeMs` and `fileSize` to `Song`, populated via `statSync` on
  desktop/iOS and `DATE_MODIFIED`/`SIZE` from MediaStore on Android
- Adds `SonoQuery.fingerprint()` as the canonical fingerprint format so
  consumers store and compare the same string the scanner produces
- Adds `getCoverThumbnail()` for downscaled cover art via MediaStore
  `loadThumbnail` on Android Q+. Returns null elsewhere so callers can
  fall back to `getCover()`
- Fixes a pre-Android-Q crash in `getCoverFromMediaStore`:
  `loadThumbnail` is API 29+ and throws `NoSuchMethodError` (an `Error`,
  not caught by the existing `catch`) on older devices. Now gated and
  returns null, falling through to embedded art
- Hoists the `TRACK` column index lookup out of the MediaStore cursor loop

## 0.6.2

- Adds `MetadataReader.writeAsync()` for cross-platform tag editing. On
  Android handles scoped storage by copying to app cache, writing tags there,
  then prompting the user via `MediaStore.createWriteRequest()` to commit the
  bytes back to the original file. Desktop falls through to `writeSync()`
- Adds `resolveContentUri()`, `copyToAppCache()`, and `commitFromCache()` to
  the platform interface to support the above
- Makes the Android plugin `ActivityAware` so the system permission dialog
  can be launched
- Logs writeSync/writeAsync failures via `print` instead of silently
  swallowing them
- Fixes the Android plugin failing to build with "Unresolved reference: kotlin"
  by applying `org.jetbrains.kotlin.android` (the `kotlin {}` extension needs
  the Kotlin plugin applied, not just `com.android.library`)
- Declares `READ_MEDIA_AUDIO` (Android 13+) and legacy
  `READ_EXTERNAL_STORAGE` (max API 32) in the plugin manifest so consumers
  inherit them

## 0.6.0

- Adds `MetadataReader.writeSync()` for MP3, M4A, FLAC, WAV
- Re-exports `Picture` and `PictureType`
- Triggers MediaStore rescan on Android after write
- Lowers sdk constraint to ^3.11.1

## 0.5.0

- Migrates to built-in Kotlin. The plugin no longer applies the
  Kotlin Gradle Plugin directly, which removes KGP depcreation
  warning I got and prepares the plugin for AGP 9.0
- Bumps minimum Flutter to 3.44 and minimum Dart to 3.12
  since `kotlin.compilerOptions{}` requires KGP 2.0.0+

### 0.1.0 - 0.4.2

- Earlier history not tracked here
