# Changelog

## 0.6.0

- Adds SonoQuery.updateTags() for MP3, M4A, FLAC, WAV
- Re-exports Picture and PictureType
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
