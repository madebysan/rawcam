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

struct CaptureDetails {
    let mode: String
    let lens: String
    let iso: Int
    let shutter: String
    let ev: String
    let whiteBalance: String
    let clipping: String
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
    private var currentDevice: AVCaptureDevice?

    // State
    @Published var isTakingPhoto = false
    @Published var lastThumbnail: UIImage?
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published var showSavedConfirmation = false
    @Published var savedModeLabel = ""
    @Published var errorMessage: String?
    @Published var isUsingFrontCamera = false
    @Published var rawSupported = false
    @Published var lastCaptureDetails: CaptureDetails?
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
    private var frameCounter = 0

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

        session.commitConfiguration()

        updateDeviceLimits()
    }

    private func addCamera(position: AVCaptureDevice.Position) {
        for input in session.inputs {
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
            lastCaptureDetails = captureDetails(label: "BRACKET x3")
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
                        self?.lastCaptureDetails = self?.captureDetails(label: self?.captureMode.rawValue ?? "")
                        self?.showSaved(label: self?.captureMode.rawValue ?? "")
                        if let image = UIImage(data: data) {
                            self?.lastThumbnail = image
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
                        self?.lastCaptureDetails = self?.captureDetails(label: "RAW+JPG")
                        self?.showSaved(label: "RAW+JPG")
                        if let image = UIImage(data: processedData) {
                            self?.lastThumbnail = image
                        }
                    } else {
                        self?.errorMessage = "Failed to save: \(error?.localizedDescription ?? "Unknown error")"
                    }
                }
            }
        }
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

// MARK: - Histogram from Video Frames

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Process every 6th frame to save CPU
        frameCounter += 1
        guard frameCounter % 6 == 0 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

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
