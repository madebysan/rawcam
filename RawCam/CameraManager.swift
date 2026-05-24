import AVFoundation
import Photos
import UIKit
import CoreImage
import Combine

enum CaptureMode: String, CaseIterable {
    case raw = "RAW"
    case coverage = "RAW+JPG"

    var description: String {
        switch self {
        case .raw: return "Unprocessed RAW DNG"
        case .coverage: return "RAW DNG + Apple JPEG"
        }
    }
}

enum VideoCaptureFormat: String, CaseIterable, Identifiable {
    case hevc = "HEVC"
    case hevcHDR = "HDR"
    case hevcLog = "LOG"
    case proRes = "PRORES"
    case proResLog = "PRORES LOG"

    var id: String { rawValue }

    var savedLabel: String {
        switch self {
        case .hevc: return "VIDEO HEVC"
        case .hevcHDR: return "VIDEO HDR"
        case .hevcLog: return "VIDEO LOG"
        case .proRes: return "VIDEO PRORES"
        case .proResLog: return "VIDEO PRORES LOG"
        }
    }

    var codec: AVVideoCodecType {
        switch self {
        case .hevc, .hevcHDR, .hevcLog:
            return .hevc
        case .proRes, .proResLog:
            return .proRes422
        }
    }

    var wantsHDR: Bool {
        self == .hevcHDR
    }

    var wantsLog: Bool {
        self == .hevcLog || self == .proResLog
    }
}

enum WhiteBalancePreset: String, CaseIterable {
    case auto = "Auto"
    case daylight = "Daylight"
    case cloudy = "Cloudy"
    case tungsten = "Tungsten"
    case fluorescent = "Fluorescent"

    var temperatureAndTint: (Float, Float) {
        switch self {
        case .auto: return (0, 0) // handled separately
        case .daylight: return (5500, 0)
        case .cloudy: return (6500, 0)
        case .tungsten: return (3200, 0)
        case .fluorescent: return (4000, 0)
        }
    }

    var icon: String {
        switch self {
        case .auto: return "circle.lefthalf.filled"
        case .daylight: return "sun.max"
        case .cloudy: return "cloud"
        case .tungsten: return "lightbulb"
        case .fluorescent: return "fluorescent"
        }
    }
}

struct CaptureDetails: Codable, Equatable {
    let mode: String
    let lens: String
    let iso: Int
    let shutter: String
    let ev: String
    let whiteBalance: String
    let clipping: String
}

struct RawCamMediaItem: Identifiable, Codable, Equatable {
    let id: UUID
    let capturedAt: Date
    let details: CaptureDetails
    let thumbnailFilename: String?
    let mediaFilename: String?
    let mediaKind: String?
    let photosAssetIdentifier: String?
}

struct CameraLens: Identifiable, Hashable {
    let id: String
    let label: String
    let deviceType: AVCaptureDevice.DeviceType
    let rawSupported: Bool
}

class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var currentDevice: AVCaptureDevice?
    private var audioInput: AVCaptureDeviceInput?
    private var videoRecordingURL: URL?
    private var videoTimer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private var pendingVideoStopReason: String?

    // State
    @Published var isTakingPhoto = false
    @Published var lastThumbnail: UIImage?
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published var showSavedConfirmation = false
    @Published var savedModeLabel = ""
    @Published var errorMessage: String?
    @Published var isRecordingVideo = false
    @Published var videoElapsedSeconds = 0
    @Published var availableVideoFormats: [VideoCaptureFormat] = [.hevc]
    @Published var selectedVideoFormat: VideoCaptureFormat = .hevc
    @Published var isUsingFrontCamera = false
    @Published var rawSupported = false
    @Published var lastCaptureDetails: CaptureDetails?
    @Published var mediaItems: [RawCamMediaItem] = []
    @Published var availableLenses: [CameraLens] = []
    @Published var selectedLensID: String?

    // Capture mode
    @Published var captureMode: CaptureMode = .raw

    // Manual exposure
    @Published var iso: Float = 100
    @Published var shutterSpeed: Double = 1.0 / 60.0
    @Published var isManualExposure = false
    @Published var isExposureLocked = false
    @Published var exposureBias: Float = 0
    @Published var minExposureBias: Float = -2
    @Published var maxExposureBias: Float = 2
    @Published var minISO: Float = 50
    @Published var maxISO: Float = 1600
    @Published var minShutter: Double = 1.0 / 8000.0
    @Published var maxShutter: Double = 1.0
    @Published var zoomFactor: CGFloat = 1.0
    @Published var minZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 1.0

    // White balance
    @Published var whiteBalancePreset: WhiteBalancePreset = .auto
    @Published var kelvin: Float = 5500
    @Published var isManualWhiteBalance = false

    // Focus
    @Published var focusPoint: CGPoint?
    @Published var exposurePoint: CGPoint?
    @Published var isFocusLocked = false
    @Published var showFocusIndicator = false
    @Published var showExposureIndicator = false

    // Histogram
    @Published var histogramData: [UInt]  = Array(repeating: 0, count: 256)
    @Published var isShadowClipping = false
    @Published var isHighlightClipping = false

    private var isConfigured = false
    private let histogramQueue = DispatchQueue(label: "com.rawcam.histogram", qos: .utility)
    private let imageContext = CIContext()
    private var frameCounter = 0
    private var latestPreviewImage: UIImage?

    // Coverage mode storage
    private var coverageRAWData: Data?
    private var coverageProcessedData: Data?
    private var coverageExpectedCount = 0
    private var coverageReceivedCount = 0

    // Bracketing
    private let bracketOffsets: [Float] = [-1, 0, 1]
    private var isBracketing = false
    private var bracketIndex = 0
    private var bracketOriginalBias: Float = 0
    private var bracketSavedCount = 0

    override init() {
        super.init()
        loadMediaRoll()
        installReliabilityObservers()
    }

    deinit {
        videoTimer?.invalidate()
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        session.beginConfiguration()
        session.sessionPreset = .photo

        refreshAvailableLenses()
        addCamera(position: .back)

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            rawSupported = !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
        }

        // Video output for histogram
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: histogramQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            movieOutput.movieFragmentInterval = .invalid
        }

        session.commitConfiguration()

        updateDeviceLimits()
        refreshAvailableVideoFormats()

        #if DEBUG
        VideoCapabilityReporter.saveDebugReport()
        #endif
    }

    private func installReliabilityObservers() {
        let center = NotificationCenter.default
        let mainQueue = OperationQueue.main

        notificationTokens.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: mainQueue
        ) { [weak self] _ in
            self?.stopVideoRecording(reason: "Recording stopped because RawCam went to background")
        })

        notificationTokens.append(center.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: mainQueue
        ) { [weak self] _ in
            self?.stopVideoRecording(reason: "Recording stopped because RawCam was closing")
        })

        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: mainQueue
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
            self?.errorMessage = "Camera error: \(error?.localizedDescription ?? "Unknown error")"
            self?.stopVideoRecording(reason: "Recording stopped after a camera error")
        })

        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: mainQueue
        ) { [weak self] _ in
            self?.stopVideoRecording(reason: "Recording stopped after camera interruption")
        })

        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: mainQueue
        ) { [weak self] _ in
            self?.stopVideoRecording(reason: "Recording stopped after audio interruption")
        })

        notificationTokens.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: mainQueue
        ) { [weak self] _ in
            self?.stopIfThermalStateIsUnsafe()
        })
    }

    private func addCamera(position: AVCaptureDevice.Position) {
        for input in session.inputs {
            guard let deviceInput = input as? AVCaptureDeviceInput,
                  deviceInput.device.hasMediaType(.video) else { continue }
            session.removeInput(input)
        }

        let selectedDevice = availableLenses
            .first { $0.id == selectedLensID }
            .flatMap { AVCaptureDevice.default($0.deviceType, for: .video, position: position) }

        guard let device = selectedDevice ?? bestCamera(for: position) else {
            errorMessage = "No camera available"
            return
        }

        currentDevice = device
        selectedLensID = device.uniqueID

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            errorMessage = "Cannot access camera: \(error.localizedDescription)"
        }

        refreshAvailableVideoFormats()
    }

    private func ensureAudioInputIfAllowed() {
        guard audioInput == nil else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        guard let device = AVCaptureDevice.default(for: .audio) else { return }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            if session.canAddInput(input) {
                session.addInput(input)
                audioInput = input
            }
            session.commitConfiguration()
        } catch {
            errorMessage = "Cannot access microphone: \(error.localizedDescription)"
        }
    }

    private func refreshAvailableVideoFormats() {
        var formats: [VideoCaptureFormat] = [.hevc]

        let codecTypes = Set(movieOutput.availableVideoCodecTypes)
        let supportedColorSpaces = Set(currentDevice?.activeFormat.supportedColorSpaces ?? [])
        let supportsHDR = currentDevice?.activeFormat.isVideoHDRSupported == true
        var supportsLog = supportedColorSpaces.contains(.appleLog)
        if #available(iOS 26.0, *) {
            supportsLog = supportsLog || supportedColorSpaces.contains(.appleLog2)
        }

        if supportsHDR {
            formats.append(.hevcHDR)
        }
        if supportsLog {
            formats.append(.hevcLog)
        }
        if codecTypes.contains(.proRes422) {
            formats.append(.proRes)
            if supportsLog {
                formats.append(.proResLog)
            }
        }

        availableVideoFormats = formats
        if !formats.contains(selectedVideoFormat) {
            selectedVideoFormat = .hevc
        }
    }

    func cycleVideoFormat() {
        guard !isRecordingVideo else { return }
        guard let currentIndex = availableVideoFormats.firstIndex(of: selectedVideoFormat) else {
            selectedVideoFormat = availableVideoFormats.first ?? .hevc
            return
        }

        let nextIndex = availableVideoFormats.index(after: currentIndex)
        selectedVideoFormat = nextIndex == availableVideoFormats.endIndex
            ? availableVideoFormats[0]
            : availableVideoFormats[nextIndex]
    }

    func cyclePhotoFormat() {
        captureMode = captureMode == .raw ? .coverage : .raw
    }

    func resetControlsToDefaults() {
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if device.activeFormat.isVideoHDRSupported {
                device.automaticallyAdjustsVideoHDREnabled = true
            }
            device.videoZoomFactor = CGFloat(1.0).clamped(
                to: device.minAvailableVideoZoomFactor...device.maxAvailableVideoZoomFactor
            )
            setBestAvailableColorSpace([.sRGB], for: device)
            device.unlockForConfiguration()
        } catch {
            errorMessage = "Cannot reset controls: \(error.localizedDescription)"
            return
        }

        captureMode = .raw
        flashMode = .off
        selectedVideoFormat = availableVideoFormats.contains(.hevc) ? .hevc : (availableVideoFormats.first ?? .hevc)
        isManualExposure = false
        isExposureLocked = false
        exposureBias = 0
        iso = device.iso
        shutterSpeed = CMTimeGetSeconds(device.exposureDuration)
        whiteBalancePreset = .auto
        kelvin = 5500
        isManualWhiteBalance = false
        focusPoint = nil
        exposurePoint = nil
        isFocusLocked = false
        showFocusIndicator = false
        showExposureIndicator = false
    }

    private func bestCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return device
        }
        return AVCaptureDevice.default(for: .video)
    }

    private func refreshAvailableLenses() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .back
        )

        let lenses = session.devices.map { device in
            CameraLens(
                id: device.uniqueID,
                label: lensLabel(for: device.deviceType),
                deviceType: device.deviceType,
                rawSupported: !AVCapturePhotoOutput().availableRawPhotoPixelFormatTypes.isEmpty
            )
        }

        availableLenses = lenses.isEmpty
            ? bestCamera(for: .back).map {
                [CameraLens(
                    id: $0.uniqueID,
                    label: lensLabel(for: $0.deviceType),
                    deviceType: $0.deviceType,
                    rawSupported: rawSupported
                )]
            } ?? []
            : lenses
    }

    private func lensLabel(for deviceType: AVCaptureDevice.DeviceType) -> String {
        switch deviceType {
        case .builtInUltraWideCamera: return "0.5x"
        case .builtInWideAngleCamera: return "1x"
        case .builtInTelephotoCamera: return "2x"
        default: return "1x"
        }
    }

    private func updateDeviceLimits() {
        guard let device = currentDevice else { return }
        minISO = device.activeFormat.minISO
        maxISO = device.activeFormat.maxISO
        minShutter = CMTimeGetSeconds(device.activeFormat.minExposureDuration)
        maxShutter = CMTimeGetSeconds(device.activeFormat.maxExposureDuration)
        minZoomFactor = device.minAvailableVideoZoomFactor
        maxZoomFactor = min(device.maxAvailableVideoZoomFactor, 10.0)
        zoomFactor = device.videoZoomFactor.clamped(to: minZoomFactor...maxZoomFactor)
        minExposureBias = device.minExposureTargetBias
        maxExposureBias = device.maxExposureTargetBias
        exposureBias = device.exposureTargetBias.clamped(to: minExposureBias...maxExposureBias)
        iso = iso.clamped(to: minISO...maxISO)
        if let index = availableLenses.firstIndex(where: { $0.id == device.uniqueID }) {
            let updated = CameraLens(
                id: availableLenses[index].id,
                label: availableLenses[index].label,
                deviceType: availableLenses[index].deviceType,
                rawSupported: rawSupported
            )
            availableLenses[index] = updated
        }
    }

    func start() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func switchCamera() {
        session.beginConfiguration()
        isUsingFrontCamera.toggle()
        if isUsingFrontCamera {
            selectedLensID = nil
        } else if selectedLensID == nil {
            selectedLensID = availableLenses.first?.id
        }
        addCamera(position: isUsingFrontCamera ? .front : .back)
        rawSupported = !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
        session.commitConfiguration()
        updateDeviceLimits()
        // Reset locks on camera switch
        isManualExposure = false
        isExposureLocked = false
        isManualWhiteBalance = false
        isFocusLocked = false
        exposurePoint = nil
        showExposureIndicator = false
        exposureBias = 0
        whiteBalancePreset = .auto
    }

    func switchLens(to lens: CameraLens) {
        guard !isUsingFrontCamera, lens.id != selectedLensID else { return }

        session.beginConfiguration()
        selectedLensID = lens.id
        addCamera(position: .back)
        rawSupported = !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
        session.commitConfiguration()
        updateDeviceLimits()

        isManualExposure = false
        isExposureLocked = false
        isFocusLocked = false
        exposurePoint = nil
        showFocusIndicator = false
        showExposureIndicator = false
        exposureBias = 0
        setExposureBias(0)
    }

    func cycleLens() {
        guard !isUsingFrontCamera, !availableLenses.isEmpty else { return }
        guard let selectedLensID,
              let currentIndex = availableLenses.firstIndex(where: { $0.id == selectedLensID }) else {
            switchLens(to: availableLenses[0])
            return
        }

        let nextIndex = availableLenses.index(after: currentIndex)
        let lens = nextIndex == availableLenses.endIndex
            ? availableLenses[0]
            : availableLenses[nextIndex]
        switchLens(to: lens)
    }

    func setZoomFactor(_ value: CGFloat) {
        guard let device = currentDevice else { return }
        let clampedZoom = value.clamped(to: minZoomFactor...maxZoomFactor)

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clampedZoom
            device.unlockForConfiguration()
            zoomFactor = clampedZoom
        } catch {
            errorMessage = "Cannot zoom: \(error.localizedDescription)"
        }
    }

    // MARK: - Flash

    func toggleFlash() {
        switch flashMode {
        case .off: flashMode = .on
        case .on: flashMode = .auto
        case .auto: flashMode = .off
        @unknown default: flashMode = .off
        }
    }

    var flashIcon: String {
        switch flashMode {
        case .off: return "bolt.slash"
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.automatic"
        @unknown default: return "bolt.slash"
        }
    }

    // MARK: - Manual Exposure

    func setManualExposure(iso: Float, shutterSpeed: Double) {
        guard let device = currentDevice else { return }
        let clampedISO = iso.clamped(to: minISO...maxISO)
        let clampedShutter = shutterSpeed.clamped(to: minShutter...maxShutter)
        let duration = CMTimeMakeWithSeconds(clampedShutter, preferredTimescale: 1_000_000)

        do {
            try device.lockForConfiguration()
            device.setExposureModeCustom(duration: duration, iso: clampedISO)
            device.unlockForConfiguration()
            self.iso = clampedISO
            self.shutterSpeed = clampedShutter
        } catch {
            errorMessage = "Cannot set exposure: \(error.localizedDescription)"
        }
    }

    func toggleManualExposure() {
        isManualExposure.toggle()
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()
            if isManualExposure {
                // Read current auto values as starting point
                iso = device.iso
                shutterSpeed = CMTimeGetSeconds(device.exposureDuration)
                device.setExposureModeCustom(
                    duration: device.exposureDuration,
                    iso: device.iso
                )
            } else {
                device.exposureMode = .continuousAutoExposure
                isExposureLocked = false
            }
            device.unlockForConfiguration()
            if !isManualExposure {
                setExposureBias(exposureBias)
            }
        } catch {
            errorMessage = "Cannot toggle exposure: \(error.localizedDescription)"
        }
    }

    func setExposureBias(_ value: Float) {
        guard let device = currentDevice, !isManualExposure else { return }
        let clampedBias = value.clamped(to: minExposureBias...maxExposureBias)

        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(clampedBias)
            device.unlockForConfiguration()
            exposureBias = clampedBias
        } catch {
            errorMessage = "Cannot set EV: \(error.localizedDescription)"
        }
    }

    // MARK: - White Balance

    func setWhiteBalance(preset: WhiteBalancePreset) {
        whiteBalancePreset = preset
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()
            if preset == .auto {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
                isManualWhiteBalance = false
            } else {
                let (temp, tint) = preset.temperatureAndTint
                kelvin = temp
                let temperatureAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                    temperature: temp, tint: tint
                )
                let gains = device.deviceWhiteBalanceGains(for: temperatureAndTint)
                let clampedGains = clampWhiteBalanceGains(gains, for: device)
                device.setWhiteBalanceModeLocked(with: clampedGains)
                isManualWhiteBalance = true
            }
            device.unlockForConfiguration()
        } catch {
            errorMessage = "Cannot set white balance: \(error.localizedDescription)"
        }
    }

    func setKelvin(_ value: Float) {
        kelvin = value
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()
            let temperatureAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                temperature: value, tint: 0
            )
            let gains = device.deviceWhiteBalanceGains(for: temperatureAndTint)
            let clampedGains = clampWhiteBalanceGains(gains, for: device)
            device.setWhiteBalanceModeLocked(with: clampedGains)
            isManualWhiteBalance = true
            whiteBalancePreset = .auto // deselect preset
            device.unlockForConfiguration()
        } catch {
            errorMessage = "Cannot set white balance: \(error.localizedDescription)"
        }
    }

    private func clampWhiteBalanceGains(
        _ gains: AVCaptureDevice.WhiteBalanceGains,
        for device: AVCaptureDevice
    ) -> AVCaptureDevice.WhiteBalanceGains {
        let maxGain = device.maxWhiteBalanceGain
        return AVCaptureDevice.WhiteBalanceGains(
            redGain: min(max(gains.redGain, 1.0), maxGain),
            greenGain: min(max(gains.greenGain, 1.0), maxGain),
            blueGain: min(max(gains.blueGain, 1.0), maxGain)
        )
    }

    // MARK: - Focus

    func focus(at point: CGPoint, in viewSize: CGSize) {
        guard let device = currentDevice, device.isFocusPointOfInterestSupported else { return }

        // Convert view coordinates to device coordinates
        let devicePoint = CGPoint(x: point.y / viewSize.height, y: 1 - point.x / viewSize.width)

        do {
            try device.lockForConfiguration()
            device.focusPointOfInterest = devicePoint
            device.focusMode = .autoFocus
            if exposurePoint == nil && device.isExposurePointOfInterestSupported && !isExposureLocked && !isManualExposure {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()

            focusPoint = point
            showFocusIndicator = true
            isFocusLocked = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.showFocusIndicator = false
            }
        } catch {
            errorMessage = "Cannot set focus: \(error.localizedDescription)"
        }
    }

    func meterExposure(at point: CGPoint, in viewSize: CGSize) {
        guard let device = currentDevice, device.isExposurePointOfInterestSupported, !isManualExposure else { return }

        let devicePoint = CGPoint(x: point.y / viewSize.height, y: 1 - point.x / viewSize.width)

        do {
            try device.lockForConfiguration()
            device.exposurePointOfInterest = devicePoint
            device.exposureMode = .autoExpose
            device.unlockForConfiguration()

            exposurePoint = point
            showExposureIndicator = true
            isExposureLocked = false
        } catch {
            errorMessage = "Cannot set exposure point: \(error.localizedDescription)"
        }
    }

    func lockFocus(at point: CGPoint, in viewSize: CGSize) {
        guard let device = currentDevice, device.isFocusPointOfInterestSupported else { return }

        let devicePoint = CGPoint(x: point.y / viewSize.height, y: 1 - point.x / viewSize.width)

        do {
            try device.lockForConfiguration()
            device.focusPointOfInterest = devicePoint
            device.focusMode = .locked
            device.unlockForConfiguration()

            focusPoint = point
            showFocusIndicator = true
            isFocusLocked = true
        } catch {
            errorMessage = "Cannot lock focus: \(error.localizedDescription)"
        }
    }

    func lockCurrentFocusAndExposure() {
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()
            if device.isLockingFocusWithCustomLensPositionSupported || device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
                isFocusLocked = true
            }
            if !isManualExposure && device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
                isExposureLocked = true
            }
            device.unlockForConfiguration()

            showFocusIndicator = false
            showExposureIndicator = false
        } catch {
            errorMessage = "Cannot lock AF/AE: \(error.localizedDescription)"
        }
    }

    func unlockFocus() {
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()
            device.focusMode = .continuousAutoFocus
            if !isManualExposure {
                device.exposureMode = .continuousAutoExposure
                isExposureLocked = false
            }
            device.unlockForConfiguration()
            isFocusLocked = false
            exposurePoint = nil
            showFocusIndicator = false
            showExposureIndicator = false
        } catch {
            errorMessage = "Cannot unlock focus: \(error.localizedDescription)"
        }
    }

    // MARK: - Capture

    func capturePhoto(bracketed: Bool = false) {
        guard !isTakingPhoto else { return }
        guard !isRecordingVideo else {
            errorMessage = "Stop recording before taking a photo"
            return
        }

        if bracketed {
            captureBracket()
            return
        }

        isTakingPhoto = true

        switch captureMode {
        case .raw:
            captureRAW()
        case .coverage:
            captureCoverage()
        }
    }

    private func captureBracket() {
        guard captureMode == .raw else {
            errorMessage = "Bracketing is RAW only"
            return
        }
        guard !isManualExposure else {
            errorMessage = "Bracketing needs auto exposure"
            return
        }
        guard rawSupported, photoOutput.availableRawPhotoPixelFormatTypes.first != nil else {
            errorMessage = "RAW not supported on this camera"
            return
        }

        isTakingPhoto = true
        isBracketing = true
        bracketIndex = 0
        bracketSavedCount = 0
        bracketOriginalBias = exposureBias
        captureNextBracket()
    }

    private func captureNextBracket() {
        guard isBracketing else { return }

        guard bracketIndex < bracketOffsets.count else {
            finishBracket(restoreBias: true)
            showSaved(label: "BRACKET")
            let details = captureDetails(label: "BRACKET x3")
            lastCaptureDetails = details
            lastThumbnail = latestPreviewImage
            addMediaRollItem(details: details, thumbnail: latestPreviewImage, mediaKind: "photo")
            return
        }

        let targetBias = (bracketOriginalBias + bracketOffsets[bracketIndex])
            .clamped(to: minExposureBias...maxExposureBias)
        setExposureBias(targetBias)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.captureRAW()
        }
    }

    private func captureRAW() {
        guard rawSupported, let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first else {
            errorMessage = "RAW not supported on this camera"
            isTakingPhoto = false
            return
        }
        // Single RAW DNG — no pairing, most reliable
        coverageExpectedCount = 0
        let settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
        settings.flashMode = flashMode
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func captureCoverage() {
        guard rawSupported, let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first else {
            errorMessage = "RAW not supported on this camera"
            isTakingPhoto = false
            return
        }

        coverageRAWData = nil
        coverageProcessedData = nil
        coverageReceivedCount = 0
        coverageExpectedCount = 2

        // RAW + processed HEIC in one capture
        let settings = AVCapturePhotoSettings(
            rawPixelFormatType: rawFormat,
            processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc]
        )
        settings.flashMode = flashMode
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - Video

    func toggleVideoRecording() {
        isRecordingVideo ? stopVideoRecording() : requestVideoRecordingStart()
    }

    private func requestVideoRecordingStart() {
        guard !isTakingPhoto else { return }
        guard !movieOutput.isRecording else { return }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startVideoRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if !granted {
                        self?.errorMessage = "Recording without microphone audio"
                    }
                    self?.startVideoRecording()
                }
            }
        case .denied, .restricted:
            errorMessage = "Recording without microphone audio"
            startVideoRecording()
        @unknown default:
            startVideoRecording()
        }
    }

    private func startVideoRecording() {
        guard hasEnoughVideoStorage() else {
            errorMessage = "Not enough free storage to start recording"
            return
        }

        ensureAudioInputIfAllowed()

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCam-\(UUID().uuidString).mov")
        videoRecordingURL = fileURL

        guard let connection = movieOutput.connection(with: .video) else {
            errorMessage = "Video output unavailable"
            cleanupVideoFile(fileURL)
            return
        }

        connection.videoRotationAngle = isUsingFrontCamera ? 270 : 90
        applySelectedVideoFormat(to: connection)

        pendingVideoStopReason = nil
        videoElapsedSeconds = 0
        isRecordingVideo = true
        startVideoTimer()
        movieOutput.startRecording(to: fileURL, recordingDelegate: self)
    }

    private func applySelectedVideoFormat(to connection: AVCaptureConnection) {
        let format = selectedVideoFormat

        if movieOutput.availableVideoCodecTypes.contains(format.codec) {
            movieOutput.setOutputSettings([AVVideoCodecKey: format.codec], for: connection)
        } else if movieOutput.availableVideoCodecTypes.contains(.hevc) {
            selectedVideoFormat = .hevc
            movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
        }

        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()
            if format.wantsLog {
                if #available(iOS 26.0, *) {
                    setBestAvailableColorSpace([.appleLog2, .appleLog], for: device)
                } else {
                    setBestAvailableColorSpace([.appleLog], for: device)
                }
            } else if format.wantsHDR {
                if device.activeFormat.isVideoHDRSupported {
                    device.automaticallyAdjustsVideoHDREnabled = false
                    device.isVideoHDREnabled = true
                }
                setBestAvailableColorSpace([.HLG_BT2020, .P3_D65], for: device)
            } else {
                if device.activeFormat.isVideoHDRSupported {
                    device.automaticallyAdjustsVideoHDREnabled = false
                    device.isVideoHDREnabled = false
                }
                setBestAvailableColorSpace([.sRGB], for: device)
            }
            device.unlockForConfiguration()
        } catch {
            errorMessage = "Cannot set video format: \(error.localizedDescription)"
        }
    }

    private func setBestAvailableColorSpace(_ candidates: [AVCaptureColorSpace], for device: AVCaptureDevice) {
        guard let colorSpace = candidates.first(where: { device.activeFormat.supportedColorSpaces.contains($0) }) else { return }
        device.activeColorSpace = colorSpace
    }

    private func stopVideoRecording(reason: String? = nil) {
        guard movieOutput.isRecording else {
            finishVideoRecordingState()
            return
        }
        pendingVideoStopReason = reason
        movieOutput.stopRecording()
    }

    private func startVideoTimer() {
        videoTimer?.invalidate()
        videoTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.videoElapsedSeconds += 1
            self?.monitorRecordingHealth()
        }
    }

    private func finishVideoRecordingState() {
        videoTimer?.invalidate()
        videoTimer = nil
        isRecordingVideo = false
    }

    private func monitorRecordingHealth() {
        guard isRecordingVideo else { return }

        if !hasEnoughVideoStorage() {
            stopVideoRecording(reason: "Recording stopped because storage is low")
            return
        }

        if isThermalStateUnsafe {
            stopVideoRecording(reason: "Recording stopped because iPhone is too hot")
            return
        }

        if let pressureLevel = currentDevice?.systemPressureState.level,
           pressureLevel == .serious || pressureLevel == .critical || pressureLevel == .shutdown {
            stopVideoRecording(reason: "Recording stopped because camera pressure is high")
        }
    }

    private func stopIfThermalStateIsUnsafe() {
        guard isThermalStateUnsafe else { return }
        stopVideoRecording(reason: "Recording stopped because iPhone is too hot")
    }

    private var isThermalStateUnsafe: Bool {
        let state = ProcessInfo.processInfo.thermalState
        return state == .serious || state == .critical
    }

    private func hasEnoughVideoStorage(minimumBytes: Int64 = 250 * 1024 * 1024) -> Bool {
        do {
            let values = try FileManager.default.temporaryDirectory.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            )
            guard let available = values.volumeAvailableCapacityForImportantUsage else { return true }
            return available > minimumBytes
        } catch {
            return true
        }
    }

    // MARK: - Save

    private func saveToPhotos(_ data: Data, resourceType: PHAssetResourceType) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self?.errorMessage = "Photo library access denied"
                    self?.finishBracket(restoreBias: true)
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: resourceType, data: data, options: PHAssetResourceCreationOptions())
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        if self?.isBracketing == true {
                            self?.bracketSavedCount += 1
                            self?.bracketIndex += 1
                            self?.captureNextBracket()
                            return
                        }

                        self?.isTakingPhoto = false
                        let label = self?.captureMode.rawValue ?? ""
                        let details = self?.captureDetails(label: label)
                        self?.lastCaptureDetails = details
                        self?.showSaved(label: label)
                        self?.lastThumbnail = self?.latestPreviewImage
                        if let details {
                            self?.addMediaRollItem(
                                details: details,
                                thumbnail: self?.latestPreviewImage,
                                mediaKind: "photo"
                            )
                        }
                    } else {
                        self?.finishBracket(restoreBias: true)
                        self?.errorMessage = "Failed to save: \(error?.localizedDescription ?? "Unknown error")"
                    }
                }
            }
        }
    }

    private func saveCoverageToPhotos(rawData: Data, processedData: Data) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self?.errorMessage = "Photo library access denied"
                    self?.isTakingPhoto = false
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                // Save as separate assets so both are visible in Photos
                let rawRequest = PHAssetCreationRequest.forAsset()
                rawRequest.addResource(with: .photo, data: rawData, options: PHAssetResourceCreationOptions())

                let processedRequest = PHAssetCreationRequest.forAsset()
                processedRequest.addResource(with: .photo, data: processedData, options: PHAssetResourceCreationOptions())
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    self?.isTakingPhoto = false
                    if success {
                        let details = self?.captureDetails(label: "RAW+JPG")
                        self?.lastCaptureDetails = details
                        self?.showSaved(label: "RAW+JPG")
                        let thumbnail = UIImage(data: processedData)
                        self?.lastThumbnail = thumbnail
                        if let details {
                            self?.addMediaRollItem(
                                details: details,
                                thumbnail: thumbnail,
                                mediaKind: "photo"
                            )
                        }
                    } else {
                        self?.errorMessage = "Failed to save: \(error?.localizedDescription ?? "Unknown error")"
                    }
                }
            }
        }
    }

    private func saveVideoToPhotos(_ fileURL: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self?.errorMessage = "Photo library access denied"
                    self?.cleanupVideoFile(fileURL)
                }
                return
            }

            var photosAssetIdentifier: String?
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: fileURL, options: PHAssetResourceCreationOptions())
                photosAssetIdentifier = request.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        let details = self?.captureDetails(label: self?.selectedVideoFormat.savedLabel ?? "VIDEO")
                        self?.lastCaptureDetails = details
                        self?.showSaved(label: "VIDEO")
                        self?.lastThumbnail = self?.latestPreviewImage
                        if let details {
                            self?.addMediaRollItem(
                                details: details,
                                thumbnail: self?.latestPreviewImage,
                                mediaKind: "video",
                                photosAssetIdentifier: photosAssetIdentifier
                            )
                        }
                    } else {
                        self?.errorMessage = "Failed to save video: \(error?.localizedDescription ?? "Unknown error")"
                    }
                    self?.cleanupVideoFile(fileURL)
                }
            }
        }
    }

    private func cleanupVideoFile(_ fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
        if videoRecordingURL == fileURL {
            videoRecordingURL = nil
        }
    }

    private func videoFileLooksValid(_ fileURL: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }

    private func showSaved(label: String) {
        savedModeLabel = label
        showSavedConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.showSavedConfirmation = false
        }
    }

    private func captureDetails(label: String) -> CaptureDetails {
        let actualISO = currentDevice?.iso ?? iso
        let actualShutter = currentDevice.map { CMTimeGetSeconds($0.exposureDuration) } ?? shutterSpeed

        let shutterText: String
        if actualShutter >= 1 {
            shutterText = String(format: "%.1fs", actualShutter)
        } else {
            shutterText = "1/\(Int(round(1.0 / actualShutter)))"
        }

        let evText = abs(exposureBias) < 0.05 ? "0.0" : String(format: "%+.1f", exposureBias)
        let wbText = isManualWhiteBalance ? "\(Int(kelvin))K" : "AUTO"
        let clippingText: String
        switch (isShadowClipping, isHighlightClipping) {
        case (true, true): clippingText = "SHADOW + HIGHLIGHT"
        case (true, false): clippingText = "SHADOW"
        case (false, true): clippingText = "HIGHLIGHT"
        case (false, false): clippingText = "NONE"
        }

        return CaptureDetails(
            mode: label,
            lens: activeLensLabel,
            iso: Int(actualISO),
            shutter: shutterText,
            ev: evText,
            whiteBalance: wbText,
            clipping: clippingText
        )
    }

    private func finishBracket(restoreBias: Bool) {
        let wasBracketing = isBracketing
        isBracketing = false
        if restoreBias && wasBracketing {
            setExposureBias(bracketOriginalBias)
        }
        isTakingPhoto = false
    }

    func thumbnail(for item: RawCamMediaItem) -> UIImage? {
        guard let thumbnailFilename = item.thumbnailFilename else { return nil }
        return UIImage(contentsOfFile: mediaRollDirectory.appendingPathComponent(thumbnailFilename).path)
    }

    private func addMediaRollItem(
        details: CaptureDetails,
        thumbnail: UIImage?,
        mediaKind: String? = nil,
        photosAssetIdentifier: String? = nil
    ) {
        let id = UUID()
        let thumbnailFilename = saveMediaRollThumbnail(thumbnail, id: id)
        let item = RawCamMediaItem(
            id: id,
            capturedAt: Date(),
            details: details,
            thumbnailFilename: thumbnailFilename,
            mediaFilename: nil,
            mediaKind: mediaKind,
            photosAssetIdentifier: photosAssetIdentifier
        )
        mediaItems.insert(item, at: 0)
        saveMediaRoll()
    }

    private var mediaRollDirectory: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent("RawCamRoll", isDirectory: true)
    }

    private var mediaRollIndexURL: URL {
        mediaRollDirectory.appendingPathComponent("index.json")
    }

    private func loadMediaRoll() {
        do {
            try FileManager.default.createDirectory(at: mediaRollDirectory, withIntermediateDirectories: true)
            guard FileManager.default.fileExists(atPath: mediaRollIndexURL.path) else { return }
            let data = try Data(contentsOf: mediaRollIndexURL)
            mediaItems = try JSONDecoder().decode([RawCamMediaItem].self, from: data)
        } catch {
            mediaItems = []
        }
    }

    private func saveMediaRoll() {
        do {
            try FileManager.default.createDirectory(at: mediaRollDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(mediaItems)
            try data.write(to: mediaRollIndexURL, options: .atomic)
        } catch {
            errorMessage = "Saved to Photos, but RawCam roll could not update."
        }
    }

    private func saveMediaRollThumbnail(_ image: UIImage?, id: UUID) -> String? {
        guard let image, let data = image.jpegData(compressionQuality: 0.78) else { return nil }
        let filename = "\(id.uuidString).jpg"

        do {
            try FileManager.default.createDirectory(at: mediaRollDirectory, withIntermediateDirectories: true)
            try data.write(to: mediaRollDirectory.appendingPathComponent(filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    private var activeLensLabel: String {
        guard let currentDevice else { return "1x" }
        return lensLabel(for: currentDevice.deviceType)
    }
}

// MARK: - Photo Delegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.errorMessage = "Capture failed: \(error.localizedDescription)"
                self.finishBracket(restoreBias: true)
            }
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                self.finishBracket(restoreBias: true)
            }
            return
        }

        if coverageExpectedCount == 2 {
            if photo.isRawPhoto {
                coverageRAWData = data
            } else {
                coverageProcessedData = data
            }
            coverageReceivedCount += 1

            if coverageReceivedCount >= coverageExpectedCount {
                if let raw = coverageRAWData, let processed = coverageProcessedData {
                    saveCoverageToPhotos(rawData: raw, processedData: processed)
                } else {
                    saveToPhotos(data, resourceType: .photo)
                }
            }
        } else {
            saveToPhotos(data, resourceType: .photo)
        }
    }
}

// MARK: - Movie Delegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.finishVideoRecordingState()
            let stopReason = self.pendingVideoStopReason
            self.pendingVideoStopReason = nil

            if let error {
                self.errorMessage = "Recording failed: \(error.localizedDescription)"
                self.cleanupVideoFile(outputFileURL)
                return
            }

            guard self.videoFileLooksValid(outputFileURL) else {
                self.errorMessage = stopReason ?? "Recording failed: empty video file"
                self.cleanupVideoFile(outputFileURL)
                return
            }

            if let stopReason {
                self.errorMessage = stopReason
            }
            self.saveVideoToPhotos(outputFileURL)
        }
    }
}

// MARK: - Histogram from Video Frames

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Process every 6th frame to save CPU
        frameCounter += 1
        guard frameCounter % 6 == 0 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if latestPreviewImage == nil || frameCounter % 18 == 0 {
            updateLatestPreviewImage(from: pixelBuffer)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var histogram = [UInt](repeating: 0, count: 256)

        // Sample every 4th pixel for performance
        let step = 4
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let offset = y * bytesPerRow + x * 4
                let b = UInt16(buffer[offset])
                let g = UInt16(buffer[offset + 1])
                let r = UInt16(buffer[offset + 2])
                // Luminance approximation
                let lum = (r * 77 + g * 150 + b * 29) >> 8
                histogram[Int(min(lum, 255))] += 1
            }
        }

        DispatchQueue.main.async {
            self.histogramData = histogram
            self.updateClippingFlags(from: histogram)
        }
    }

    private func updateLatestPreviewImage(from pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let sourceExtent = ciImage.extent
        let maxDimension = max(sourceExtent.width, sourceExtent.height)
        let scale = 900 / maxDimension
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = imageContext.createCGImage(scaledImage, from: scaledImage.extent) else { return }

        let orientation: UIImage.Orientation = isUsingFrontCamera ? .leftMirrored : .right
        let image = UIImage(cgImage: cgImage, scale: 1, orientation: orientation)

        DispatchQueue.main.async {
            self.latestPreviewImage = image
        }
    }

    private func updateClippingFlags(from histogram: [UInt]) {
        let total = histogram.reduce(UInt(0), +)
        guard total > 0 else {
            isShadowClipping = false
            isHighlightClipping = false
            return
        }

        let edgeBinCount = 4
        let shadowCount = histogram.prefix(edgeBinCount).reduce(UInt(0), +)
        let highlightCount = histogram.suffix(edgeBinCount).reduce(UInt(0), +)
        let threshold = Double(total) * 0.01

        isShadowClipping = Double(shadowCount) > threshold
        isHighlightClipping = Double(highlightCount) > threshold
    }

}

// MARK: - Helpers

extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
