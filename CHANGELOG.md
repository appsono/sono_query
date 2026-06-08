# Changelog

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
