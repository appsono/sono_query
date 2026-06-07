/// List of audio extensions
/// List may extend with growing support by audio_metadata_reader
const audioExtensions = [
  // read + writable
  '.mp3', '.m4a', '.flac', '.wav',
  // read + non writable
  '.ogg', '.opus',
  // read only
  '.aiff', '.aifc', '.ape',
];

/// Extensions where audio_metadata_reader supports tag writing
const writeableExtensions = {'.mp3', '.m4a', '.flac', '.wav'};

// .mp4 would be supported, but I'm only focusing
// on audio formats here
