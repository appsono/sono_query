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

## Scan Configuration

Pass a `ScanConfig` to control filtering and artist parsing:

```dart
final config = ScanConfig(
  // Skip these directories entirely
  excludedPaths: [
    '/storage/emulated/0/Ringtones',
    '/storage/emulated/0/Music/trashSongs',
  ],

  // Scan additional directories (desktop only, ~/Music is always included)
  additionalPaths: [
    '/home/user/Downloads/Music',
  ];

  // Skip songs shorter than 10 seconds
  minDuration: const Duration(seconds: 10),

  // Enable multi-artist parsing (see below)
  artistParser: const ArtistParserConfig(),
);
```

### Excluded Paths

Songs whose file paths start with any excluded prefix are filtered out.
On Android this is pushed into the MediaStore `WHERE` clause (`DATA NOT LIKE ?`).
On desktop/iOS it's applied during the directory walk.

### Additional Paths (desktop only)

By default only `~/Music` (Linux) or `%USERPROFILE%\Music` (Windows) is scanned.
Additional paths are scanned alongside it.

### Minimum Duration

Songs shorter than `minDuration` are skipped.
On Android this is a MediaStore `WHERE` clause (`DURATION > ?`).
On desktop/iOS it's applied after metadata reading.

## Multi-Artist Parsing

Songs downloaded with yt-dlp or other tools often store multiple artists in a single tag separated by `/`, `;`, `,`, etc. `ArtistParserConfig` splits these automatically.

```dart
final config = ScanConfig(
  artistParser: ArtistParserConfig(
    // These are the defaults; override to customize
    delimiters: [' / ', '; ', ';', ' + ', ', ', '/'],

    // Artist names that should never be split,
    // even if they contain a delimiter
    excludedArtists: ['Tyler, The Creator', 'mathis + the world'],
  ),
);

final songs = await SonoQuery.getSongs(config: config);
for (final song in songs) {
  print(song.artist);   // raw tag: "Jay-Z / Kanye West"
  print(song.artists);  // parsed: ["Jay-Z", "Kanye West"]
}
```

### Escape Character

Use backslash (`\`) before a character to prevent splitting:

| Raw tag              | Parsed result              |
| -------------------- | -------------------------- |
| `Artist / Artist2`   | `["Artist1", "Artist2"]`   |
| `A + B + C`          | `["A", "B", "C"]`          |
| `AC\/DC`             | `["AC/DC"]`                |
| `AC\/DC / Someone`   | `["AC/DC", "Someone"]`     |

### Standalone Usage

`ArtistParser` can also be used independently from scanning:

```dart
final artists = ArtistParser.parse(
  'Tyler, The Creator, Someone',
  ArtistParserConfig(excludedArtists: ['Tyler, The Creator']),
)
// -> ["Tyler, The Creator", "Someone"]
```

## Scan Progress

Both `getSongs` and `getSongsStream` accept an `onProgress` callback for live progress reporting:

```dart
final songs = await SonoQuery.getSongs(
  onProgress: (progress) {
    print('${progress.phase.name}: '
        '${progress.completed}/${progress.total} '
        '(${(progress.progress * 100).toStringAsFixed(0)}%)');
    if (progress.currentPath != null) {
      print('  → ${progress.currentPath}');
    }
  },
);
```

`ScanProgress` fields:
 
| Field                   | Type                         | Description                        |
|-------------------------|------------------------------|----------------------------------- |
| `total`                 | `int`                        | Total files discovered             |
| `completed`             | `int`                        | Files processed so far             |
| `progress`              | `double`                     | 0.0 - 1.0 fraction                 |
| `currentPath`           | `String?`                    | File currently being processed     |
| `phase`                 | `ScanPhase`                  | `discovering` > `reading` > `done` |

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
Add more directories via `ScanConfig.additionalPaths`.

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
