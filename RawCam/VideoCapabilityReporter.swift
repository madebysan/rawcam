import AVFoundation
import CoreMedia

struct VideoCapabilityReporter {
    static func makeReport() -> String {
        var lines: [String] = [
            "RawCam Video Capability Audit",
            "Generated: \(Date().formatted(date: .numeric, time: .standard))",
            ""
        ]

        let movieOutput = AVCaptureMovieFileOutput()
        let codecTypes = movieOutput.availableVideoCodecTypes.map(\.rawValue).sorted()
        lines.append("Movie output codec types: \(codecTypes.isEmpty ? "unavailable until session-bound" : codecTypes.joined(separator: ", "))")
        lines.append("")

        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInTripleCamera
        ]

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )

        if session.devices.isEmpty {
            lines.append("No video capture devices found.")
        }

        for device in session.devices {
            appendDevice(device, to: &lines)
        }

        lines.append("")
        lines.append("Notes:")
        lines.append("- Codec availability can change after a concrete capture session and output are configured.")
        lines.append("- External-storage requirements are not exposed as a simple static format flag; verify during recording tests.")
        lines.append("- This audit is read-only and does not start video recording.")

        return lines.joined(separator: "\n")
    }

    static func saveDebugReport() {
        let report = makeReport()
        print(report)

        do {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let directory = baseURL.appendingPathComponent("Debug", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try report.write(
                to: directory.appendingPathComponent("video-capabilities.txt"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            print("RawCam video capability report could not be saved: \(error.localizedDescription)")
        }
    }

    private static func appendDevice(_ device: AVCaptureDevice, to lines: inout [String]) {
        lines.append("Device: \(device.localizedName)")
        lines.append("- position: \(positionLabel(device.position))")
        lines.append("- type: \(device.deviceType.rawValue)")
        lines.append("- uniqueID: \(device.uniqueID)")
        lines.append("- format count: \(device.formats.count)")

        let summaries = summarizeFormats(device.formats)
        for summary in summaries {
            lines.append("- \(summary)")
        }

        lines.append("")
    }

    private static func summarizeFormats(_ formats: [AVCaptureDevice.Format]) -> [String] {
        let grouped = Dictionary(grouping: formats) { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let pixelFormat = fourCC(format.formatDescription.mediaSubType.rawValue)
            let hdr = format.isVideoHDRSupported ? "HDR" : "SDR"
            let colorSpaces = format.supportedColorSpaces
                .map(colorSpaceLabel)
                .sorted()
                .joined(separator: "/")
            return "\(dimensions.width)x\(dimensions.height) \(pixelFormat) \(hdr) \(colorSpaces)"
        }

        return grouped
            .map { key, formats in
                let ranges = formats
                    .flatMap { $0.videoSupportedFrameRateRanges }
                    .map { range in
                        "\(Int(range.minFrameRate.rounded()))-\(Int(range.maxFrameRate.rounded()))fps"
                    }
                    .uniqueSorted()
                    .joined(separator: ", ")
                return "\(key): \(ranges)"
            }
            .sorted()
    }

    private static func positionLabel(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .back: return "back"
        case .front: return "front"
        case .unspecified: return "unspecified"
        @unknown default: return "unknown"
        }
    }

    private static func colorSpaceLabel(_ colorSpace: AVCaptureColorSpace) -> String {
        switch colorSpace {
        case .sRGB: return "sRGB"
        case .P3_D65: return "P3"
        case .HLG_BT2020: return "HLG"
        case .appleLog: return "AppleLog"
        case .appleLog2: return "AppleLog2"
        @unknown default: return "unknown"
        }
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let scalars = [
            UnicodeScalar((code >> 24) & 255),
            UnicodeScalar((code >> 16) & 255),
            UnicodeScalar((code >> 8) & 255),
            UnicodeScalar(code & 255)
        ]

        return scalars
            .compactMap { $0 }
            .map { String($0) }
            .joined()
    }
}

private extension Array where Element == String {
    func uniqueSorted() -> [String] {
        Array(Set(self)).sorted()
    }
}
