import Flutter
import UIKit

public class SonoQueryPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "sono_query", binaryMessenger: registrar.messenger())
        let instance = SonoQueryPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getAudioFilePaths":
            result(getAudioFilePaths())   
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func getAudioFilePaths() -> [String] {
        var paths: [String] = []
        let fileManager = FileManager.default

        // Scan Documents dir for audio files
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            scanDirectory(at: documentsURL, into: &paths)
        }

        // Scan Music dir  if accessible
        if let musicURL = fileManager.urls(for: .musicDirectory, in: .userDomainMask).first {
            scanDirectory(at: musicURL, into: &paths)
        }

        return paths
    }

    private func scanDirectory(at url: URL, into paths: inout [String]) {
        let extensions = ["mp3", "flac", "ogg", "m4a", "wav", "opus"] 
        // mp4 would be supported too, but it's not required in my use case
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) else { return}

        while let fileURL = enumerator.nextObject() as? URL {
            if extensions.contains(fileURL.pathExtension.lowercased()) {
                paths.append(fileURL.path)
            }
        }
    }
}
