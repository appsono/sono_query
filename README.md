# sono_query

Audio file discovery and metadata reading for [Sono](https://github.com/appsono/sono-new).

## Usage

**Step 1.** Add this to your pubspec.yaml in the dependencies section:
```yml
  sono_query:
    git:
      url: https://github.com/appsono/sono_query/.git
      ref: <current_tag>
```

**Step 2.** Add the import and start querying:
```dart
import 'package:sono_query/sono_query.dart';

final songs = await SonoQuery.getSongs();
```

## Supported Platforms

| Platform | Method |
| ---------|------- |
| Android  | MediaStore |
| iOS      | FileManager |
| Linux    | dart:io |
| Windows  | dart:io |

## Supported Formats

MP3, M4A, FLAC, OGG, Opus, WAV

Metadata reading by [audio_metadata_reader](https://pub.dev/packages/audio_metadata_reader)

## LICENSE

MIT