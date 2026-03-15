# sono_query

Audio file discovery and metadata reading for [Sono](https://github.com/appsono/sono-new).

## Usage

**Step 1.** Add this to your pubspec.yaml in the dependencies section:
```yml
  sono_query:
    git:
      url: https://github.com/appsono/sono_query.git
      ref: <current_tag>
```

**Step 2.** Add the import and start querying:
```dart
import 'package:sono_query/sono_query.dart';

// Get all songs at once
final songs = await SonoQuery.getSongs();

// Or stream in batches, useful for large libraries (recommended)
await for (final song in SonoQuery.getSongsStream()) {
  print(song);
}
```

## Error handling

Both `getSongs` and `getSongsStream` accept an `onError` callback for files that fail metadata reading. Failed files are skipped, scanning continues:

```dart
final songs = await SonoQuery.getSongs(
  onError: (path, error) => print('Failed to read $path: $error'),
);
```

### Cover art

```dart
final cover = await SonoQuery.getCover('/path/to/song.mp3');
// Returns Uint8List? (JPEG, PNG, or WebP bytes)
```

## Permissions

Of course all of this won't work without permission

### Android

Add to your `AndroidManifest.xml`:

```xml
<!-- Android 13+ (API 33) -->
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />

<!-- Android 12 and below -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" 
    android:maxSdkVersion="32" />
```

Must be requested at runtime before calling `SonoQuery.getSongs()`.
Without it, the query WILL return an empty list.

### iOS

Add to your `Info.plist` if scanning outside the app sandbox:

```xml
<key>UIFileSharingEnabled</key>
<true/>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
```

It scans the app's Documents and Music directories by default.
Files must be added to these directories through the Files app or iTunes file sharing.

### Linux / Windows

No special permissions needed. Scans `~/Music` (Linux) or `%USERPROFILE%\Music` (Windows).

## Supported Platforms

| Platform | Method       | Metadata source       |
| ---------|--------------|-----------------------|
| Android  | MediaStore   | MediaStore            |
| iOS      | FileManager  | audio_metadata_reader |
| Linux    | dart:io      | audio_metadata_reader |
| Windows  | dart:io      | audio_metadata_reader |

## Supported Formats

MP3, M4A, FLAC, OGG, Opus, WAV

Metadata reading by [audio_metadata_reader](https://pub.dev/packages/audio_metadata_reader)

## LICENSE

MIT
