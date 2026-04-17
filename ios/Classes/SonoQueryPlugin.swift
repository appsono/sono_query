import Flutter
import UIKit
import AVFoundation

public class SonoQueryPlugin: NSObject, FlutterPlugin {
    private static let audioExtensions: Set<String> = ["mp3", "flac", "ogg", "m4a", "wav", "opus"]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "sono_query", binaryMessenger: registrar.messenger())
        let instance = SonoQueryPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getAudioFilePaths":
            result(getAudioFilePaths())
        case "getSongsWithMetadata":
            let args = call.arguments as? [String: Any]
            let minDurationMs = args?["minDurationms"] as? Int
            let excludedPaths = args?["excludedPaths"] as? [String] ?? []
            result(getSongsWithMetadata(minDurationMs: minDurationMs, excludedPaths: excludedPaths))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func getAudioFilePaths() -> [String] {
        var paths: [String] = []
        let fileManager = FileManager.default

        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            scanDirectory(at: documentsURL, into: &paths)
        }
        if let musicURL = fileManager.urls(for: .musicDirectory, in: .userDomainMask).first {
            scanDirectory(at: musicURL, into: &paths)
        }

        return paths
    }

    private func getSongsWithMetadata(minDurationMs: Int?, excludedPaths: [String]) -> [[String: Any?]] {
        let paths = getAudioFilePaths()
        var songs: [[String: Any?]] = []

        for path in paths {
            if excludedPaths.contains(where: { path.hasPrefix($0) }) {
                continue
            }

            let url = URL(fileURLWithPath: path)
            let asset = AVURLAsset(url: url)
            let durationMs = Int(CMTimeGetSeconds(asset.duration) * 1000)

            if let minMs = minDurationMs, durationMs < minMs {
                continue
            }

            var title: String? = nil
            var artist: String? = nil
            var album: String? = nil
            var genre: String? = nil
            var year: Int? = nil

            let metadata = asset.commonMetadata
            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    title = item.stringValue
                case .commonKeyArtist:
                    artist = item.stringValue
                case .commonKeyAlbumName:
                    album = item.stringValue
                case .commonKeyType:
                    genre = item.stringValue
                case .commonKeyCreationDate:
                    if let dateStr = item.stringValue {
                        //tags often store just the year as "2024" or a full date
                        let trimmed = String(dateStr.prefix(4))
                        year = Int(trimmed)
                    }
                default:
                    break
                }
            }

            //fallback: check ID3/iTunes metadata for genre if not found
            if genre == nil {
                for item in asset.metadata {
                    if let id3Key = item.key as? String, id3Key == "TCON" {
                        genre = item.stringValue
                        break
                    }
                    if let identifier = item.identifier,
                       identifier == .iTunesMetadataUserGenre || identifier == .id3MetadataContentType {
                        genre = item.stringValue
                        break
                    }
                }
            }

            songs.append([
                "path": path,
                "title": title,
                "artist": artist,
                "album": album,
                "duration": durationMs > 0 ? durationMs : nil,
                "genre": genre,
                "year": year,
            ])
        }

        return songs
    }

    private func scanDirectory(at url: URL, into paths: inout [String]) {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) else { return }

        while let fileURL = enumerator.nextObject() as? URL {
            if SonoQueryPlugin.audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                paths.append(fileURL.path)
            }
        }
    }
}
