#if !APPSTORE
import AppKit
import AVFoundation
import ImageIO
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers
import Vision

// MARK: - Screen recording (ScreenCaptureKit, straight to a movie file)
//
// The main display with what the Mac plays and, if asked, the microphone, recorded by macOS into
// ~/Movies/Rafiq. Rafiq's own windows are left out. Nothing runs until the user starts it.

@MainActor
final class ScreenRecorder: NSObject, ObservableObject {
    static let shared = ScreenRecorder()
    static let micKey = "recorder.microphone"

    @Published private(set) var recording = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var elapsed: TimeInterval = 0
    private var ticker: Timer?
    @Published private(set) var lastFile: URL?
    @Published private(set) var failure: String?

    private var stream: SCStream?
    private var output: SCRecordingOutput?

    static var folder: URL {
        let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("Rafiq", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func toggle() {
        if recording { stop() } else { Task { await start() } }
    }

    func start() async {
        failure = nil
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            failure = String(localized: "recorder.permission", defaultValue: "Allow Rafiq in Screen & System Audio Recording, then try again.")
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let screen = NSScreen.main
            let displayID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else { return }
            let own = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            let config = SCStreamConfiguration()
            let scale = Int(screen?.backingScaleFactor ?? 2)
            config.width = display.width * scale
            config.height = display.height * scale
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.showsCursor = true
            config.capturesAudio = true
            config.captureMicrophone = UserDefaults.standard.bool(forKey: Self.micKey)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let stamp = formatter.string(from: Date())
            let file = Self.folder.appendingPathComponent("Rafiq \(stamp).mov")
            let recordingConfig = SCRecordingOutputConfiguration()
            recordingConfig.outputURL = file
            recordingConfig.outputFileType = .mov
            recordingConfig.videoCodecType = .hevc
            let recordingOutput = SCRecordingOutput(configuration: recordingConfig, delegate: self)
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addRecordingOutput(recordingOutput)
            try await stream.startCapture()
            self.stream = stream
            self.output = recordingOutput
            lastFile = file
            recording = true
            startedAt = Date()
            elapsed = 0
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in
                    if let start = ScreenRecorder.shared.startedAt { ScreenRecorder.shared.elapsed = Date().timeIntervalSince(start) }
                }
            }
        } catch {
            failure = error.localizedDescription
        }
    }

    func stop() {
        guard let stream else { return }
        Task {
            try? await stream.stopCapture()
            self.stream = nil
            self.output = nil
            recording = false
            startedAt = nil
            ticker?.invalidate()
            ticker = nil
            if let file = lastFile { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        }
    }
}

extension ScreenRecorder: SCRecordingOutputDelegate {
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            ScreenRecorder.shared.failure = message
            ScreenRecorder.shared.recording = false
        }
    }
}

// MARK: - Window capture, QR codes

enum CaptureExtras {
    /// A window, chosen with a click, copied and saved next to the other captures.
    @MainActor static func window() {
        let file = ScreenRecorder.folder.deletingLastPathComponent()
            .appendingPathComponent("Rafiq Window \(Int(Date().timeIntervalSince1970)).png")
        Task.detached {
            _ = JarvisMac.run("/usr/sbin/screencapture", ["-i", "-w", "-o", file.path], timeout: 120)
            guard let data = try? Data(contentsOf: file) else { return }
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setData(data, forType: .png)
            }
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// The text of the QR code (or barcode) in the area the user selects; it goes to the clipboard.
    static func readCode() async -> String? {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("rafiq-qr-\(UUID().uuidString).png").path
        let found: String? = await Task.detached {
            _ = JarvisMac.run("/usr/sbin/screencapture", ["-i", "-x", path], timeout: 120)
            defer { try? FileManager.default.removeItem(atPath: path) }
            guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let request = VNDetectBarcodesRequest()
            try? VNImageRequestHandler(cgImage: image).perform([request])
            return request.results?.compactMap(\.payloadStringValue).first
        }.value
        guard let found else { return nil }
        await MainActor.run { ClipboardHistory.shared.write(found) }
        return found
    }
}

// MARK: - Camera preview

@MainActor
final class CameraPreview: ObservableObject {
    static let shared = CameraPreview()
    let session = AVCaptureSession()
    @Published private(set) var running = false
    @Published private(set) var denied = false

    func start() {
        guard !running else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in Task { @MainActor in ok ? self.start() : (self.denied = true) } }
            return
        case .authorized: break
        default: denied = true; return
        }
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        nonisolated(unsafe) let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        running = true
    }

    func stop() {
        guard running else { return }
        nonisolated(unsafe) let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
        running = false
    }
}

struct CameraView: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))   // a mirror, as in FaceTime
        view.layer = layer
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Media tools (all on this Mac)

enum MediaTools {
    enum Kind { case video, image, other }

    static func kind(of url: URL) -> Kind {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return .other }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .image) { return .image }
        return .other
    }

    static func sibling(_ url: URL, suffix: String, ext: String) -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent().appendingPathComponent(suffix.isEmpty ? "\(base).\(ext)" : "\(base) \(suffix).\(ext)")
    }

    /// A smaller copy of a video (HEVC, at most 1080p) next to it.
    static func compress(_ url: URL) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVC1920x1080) else { return nil }
        let out = sibling(url, suffix: "compressed", ext: "mov")
        try? FileManager.default.removeItem(at: out)
        do { try await export.export(to: out, as: .mov) } catch { return nil }
        return out
    }

    /// A GIF of the first seconds of a video (10 frames a second, 480 px wide).
    static func gif(_ url: URL, seconds: Double = 8) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let length = min(seconds, duration.seconds)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let out = sibling(url, suffix: "", ext: "gif")
        let count = max(1, Int(length * 10))
        guard let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, count, nil) else { return nil }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary
        for i in 0..<count {
            let time = CMTime(seconds: Double(i) / 10, preferredTimescale: 600)
            if let image = try? await generator.image(at: time).image { CGImageDestinationAddImage(destination, image, frame) }
        }
        return CGImageDestinationFinalize(destination) ? out : nil
    }

    /// An image converted (JPEG, PNG or HEIC), at most `maxSide` pixels.
    static func convert(_ url: URL, to type: UTType, maxSide: Int = 2400) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxSide,
                       kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let ext = type.preferredFilenameExtension ?? "jpg"
        let out = sibling(url, suffix: "converted", ext: ext)
        guard let destination = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? out : nil
    }

    /// The text in an image, copied.
    static func text(in url: URL) -> String? {
        guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let text = JarvisMac.recognize(image)
        return text.isEmpty ? nil : text
    }
}
#endif
