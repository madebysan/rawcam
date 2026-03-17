import SwiftUI
import AVFoundation

// MARK: - Theme

private enum Theme {
    static let bg          = Color(red: 0.05, green: 0.05, blue: 0.05)
    static let panel       = Color(red: 0.09, green: 0.09, blue: 0.09)
    static let surface     = Color(red: 0.14, green: 0.14, blue: 0.14)
    static let surfaceHigh = Color(red: 0.20, green: 0.20, blue: 0.20)
    static let accent      = Color.white
    static let accentCov   = Color.white
    static let textPrimary   = Color.white
    static let textSecondary = Color(white: 0.55)
    static let textTertiary  = Color(white: 0.30)

    static let tapSpring = Animation.spring(response: 0.25, dampingFraction: 0.6)
}

// MARK: - Camera View

struct CameraView: View {
    @StateObject private var camera = CameraManager()
    @State private var showPermissionDenied = false
    @State private var viewSize: CGSize = .zero

    // Panel state
    @State private var showHelp = false

    // Shutter animation
    @State private var shutterPulse = 0
    @State private var flashOverlay = false

    private let hapticMedium = UIImpactFeedbackGenerator(style: .medium)
    private let hapticHeavy  = UIImpactFeedbackGenerator(style: .heavy)

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Full-screen preview ──────────────────────────────
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
                    .onAppear { viewSize = geo.size }
                    .onChange(of: geo.size) { _, s in viewSize = s }
                    .gesture(focusGestures)
            }
            .ignoresSafeArea()

            // Flash white overlay on capture
            if flashOverlay {
                Color.white.opacity(0.25)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Focus indicator
            if camera.showFocusIndicator, let pt = camera.focusPoint {
                FocusSquare(isLocked: camera.isFocusLocked)
                    .position(pt)
            }

            // ── Top bar ──────────────────────────────────────────
            VStack {
                topBar
                Spacer()
            }

            // ── Bottom controls ───────────────────────────────────
            mainControls
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
        }
        .animation(.easeOut(duration: 0.08), value: flashOverlay)
        .animation(Theme.tapSpring, value: camera.showFocusIndicator)
        .preferredColorScheme(.dark)
        .onAppear {
            hapticMedium.prepare()
            hapticHeavy.prepare()
            checkPermissionAndStart()
        }
        .alert("Camera Access Required", isPresented: $showPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("RawCam needs camera access to take unprocessed photos.")
        }
        .sheet(isPresented: $showHelp) {
            HelpSheet()
        }
    }

    // MARK: - Focus Gestures

    private var focusGestures: some Gesture {
        SimultaneousGesture(
            SpatialTapGesture().onEnded { v in
                hapticMedium.impactOccurred()
                hapticMedium.prepare()
                camera.focus(at: v.location, in: viewSize)
            },
            LongPressGesture(minimumDuration: 0.5)
                .sequenced(before: SpatialTapGesture())
                .onEnded { v in
                    switch v {
                    case .second(true, let tap):
                        if let loc = tap?.location {
                            hapticHeavy.impactOccurred()
                            hapticHeavy.prepare()
                            camera.lockFocus(at: loc, in: viewSize)
                        }
                    default: break
                    }
                }
        )
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center) {
            // Left — histogram
            BarHistogram(data: camera.histogramData)
                .frame(width: 56, height: 28)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Center — mode selector
            modeBadge
                .frame(maxWidth: .infinity, alignment: .center)

            // Right — flash
            Button {
                hapticMedium.impactOccurred()
                hapticMedium.prepare()
                camera.toggleFlash()
            } label: {
                Image(systemName: camera.flashIcon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
    }

    private var modeBadge: some View {
        Button {
            hapticMedium.impactOccurred()
            hapticMedium.prepare()
            withAnimation(Theme.tapSpring) {
                camera.captureMode = camera.captureMode == .raw ? .coverage : .raw
            }
        } label: {
            HStack(spacing: 2) {
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(camera.captureMode == mode ? Theme.bg : .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            camera.captureMode == mode ? modeAccent : Color.clear,
                            in: Capsule()
                        )
                }
            }
            .padding(3)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var modeAccent: Color {
        camera.captureMode == .coverage ? Theme.accentCov : Theme.accent
    }

    private var shutterLabel: String {
        if camera.isManualExposure {
            let ss = camera.shutterSpeed
            if ss >= 1 { return String(format: "%.1fs", ss) }
            return "1/\(Int(round(1.0 / ss)))"
        }
        return "AUTO"
    }

    // MARK: - Exposure Panel

    private var exposurePanel: some View {
        VStack(spacing: 14) {
            Divider().background(Theme.surfaceHigh).padding(.horizontal, 16)

            // Manual toggle
            HStack {
                Text(camera.isManualExposure ? "MANUAL" : "AUTO")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(camera.isManualExposure ? Theme.accent : Theme.textTertiary)
                    .tracking(2)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { camera.isManualExposure },
                    set: { _ in
                        hapticMedium.impactOccurred()
                        camera.toggleManualExposure()
                    }
                ))
                .tint(Theme.accent)
                .labelsHidden()
                .scaleEffect(0.85)
            }
            .padding(.horizontal, 20)

            if camera.isManualExposure {
                // ISO slider
                ExposureSlider(
                    label: "ISO",
                    valueText: "\(Int(camera.iso))",
                    value: Binding(
                        get: { Double(camera.iso) },
                        set: { camera.iso = Float($0) }
                    ),
                    range: Double(camera.minISO)...Double(camera.maxISO),
                    onRelease: { camera.setManualExposure(iso: camera.iso, shutterSpeed: camera.shutterSpeed) }
                )
                .padding(.horizontal, 20)

                // Shutter slider
                ExposureSlider(
                    label: "SHUTTER",
                    valueText: shutterLabel,
                    value: Binding(
                        get: { log2(camera.shutterSpeed) },
                        set: { camera.shutterSpeed = pow(2, $0) }
                    ),
                    range: log2(camera.minShutter)...log2(camera.maxShutter),
                    onRelease: { camera.setManualExposure(iso: camera.iso, shutterSpeed: camera.shutterSpeed) }
                )
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - WB Panel

    private var wbPanel: some View {
        VStack(spacing: 12) {
            Divider().background(Theme.surfaceHigh).padding(.horizontal, 16)

            // Presets
            HStack(spacing: 8) {
                ForEach(WhiteBalancePreset.allCases, id: \.self) { preset in
                    Button {
                        hapticMedium.impactOccurred()
                        camera.setWhiteBalance(preset: preset)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: wbIcon(preset))
                                .font(.system(size: 14))
                            Text(preset == .auto ? "AUTO" : wbShortLabel(preset))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                        }
                        .foregroundColor(camera.whiteBalancePreset == preset ? Theme.accent : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            camera.whiteBalancePreset == preset
                                ? Theme.accent.opacity(0.12)
                                : Theme.surface,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(DimPressStyle())
                }
            }
            .padding(.horizontal, 20)

            // Kelvin slider
            if camera.isManualWhiteBalance {
                HStack(spacing: 12) {
                    LinearGradient(
                        colors: [.orange, .white, Color(red: 0.6, green: 0.8, blue: 1.0)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 3)
                    .clipShape(Capsule())
                    .overlay(
                        Slider(value: $camera.kelvin, in: 2500...10000) { editing in
                            if !editing { camera.setKelvin(camera.kelvin) }
                        }
                        .tint(.clear)
                    )

                    Text("\(Int(camera.kelvin))K")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                        .frame(width: 56, alignment: .trailing)
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 8)
    }

    private func wbIcon(_ preset: WhiteBalancePreset) -> String {
        switch preset {
        case .auto:        return "circle.lefthalf.filled"
        case .daylight:    return "sun.max"
        case .cloudy:      return "cloud"
        case .tungsten:    return "lightbulb"
        case .fluorescent: return "lamp.ceiling"
        }
    }

    private func wbShortLabel(_ preset: WhiteBalancePreset) -> String {
        switch preset {
        case .auto:        return "AUTO"
        case .daylight:    return "DAY"
        case .cloudy:      return "CLOUD"
        case .tungsten:    return "TUNG"
        case .fluorescent: return "FLUO"
        }
    }

    // MARK: - Main Controls

    private var mainControls: some View {
        VStack(spacing: 10) {
            // Saved / error feedback
            ZStack {
                if camera.showSavedConfirmation {
                    Text("SAVED \(camera.savedModeLabel)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .tracking(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
                if let error = camera.errorMessage {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.75), in: Capsule())
                        .onTapGesture { camera.errorMessage = nil }
                }
            }
            .frame(height: 28)
            .animation(Theme.tapSpring, value: camera.showSavedConfirmation)

            // Shutter row: [gallery] | [shutter fixed center] | [info · flip]
            HStack(alignment: .center, spacing: 0) {
                // Left — gallery, fills equal half
                Button {
                    if let url = URL(string: "photos-redirect://") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    GalleryThumb(image: camera.lastThumbnail)
                }
                .buttonStyle(DimPressStyle())
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)

                // Center — shutter, fixed width keeps it screen-centered
                ShutterButton(
                    mode: camera.captureMode,
                    isTakingPhoto: camera.isTakingPhoto,
                    pulseCount: $shutterPulse
                ) {
                    hapticHeavy.impactOccurred()
                    hapticHeavy.prepare()
                    triggerFlash()
                    camera.capturePhoto()
                }

                // Right — equal spacers: [space] info [space] flip
                HStack(spacing: 0) {
                    Spacer()
                    Button {
                        hapticMedium.impactOccurred()
                        showHelp = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 4)
                            .frame(width: 44, height: 54)
                            .contentShape(Rectangle())
                    }
                    Spacer()
                    Button {
                        hapticMedium.impactOccurred()
                        hapticMedium.prepare()
                        camera.switchCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 4)
                            .frame(width: 44, height: 54)
                            .contentShape(Rectangle())
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Helpers

    private func triggerFlash() {
        shutterPulse += 1
        flashOverlay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            flashOverlay = false
        }
    }

    // MARK: - Permissions

    private func checkPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            camera.configure()
            camera.start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        camera.configure()
                        camera.start()
                    } else {
                        showPermissionDenied = true
                    }
                }
            }
        default:
            showPermissionDenied = true
        }
    }
}

// MARK: - Shutter Button

struct ShutterButton: View {
    let mode: CaptureMode
    let isTakingPhoto: Bool
    @Binding var pulseCount: Int
    let action: () -> Void

    private let accent: Color = .white

    var body: some View {
        ZStack {
            // Ambient glow
            Circle()
                .fill(RadialGradient(
                    colors: [accent.opacity(0.18), Color.clear],
                    center: .center, startRadius: 10, endRadius: 55
                ))
                .frame(width: 110, height: 110)

            // Pulse rings
            PulseRing(delay: 0,    maxScale: 1.9, accent: accent, trigger: $pulseCount)
                .frame(width: 72, height: 72)
            PulseRing(delay: 0.12, maxScale: 2.3, accent: accent, trigger: $pulseCount)
                .frame(width: 72, height: 72)

            // Outer ring
            Circle()
                .strokeBorder(accent.opacity(0.35), lineWidth: 1.5)
                .frame(width: 80, height: 80)

            // Button body
            Circle()
                .fill(accent)
                .frame(width: 68, height: 68)
                .shadow(color: accent.opacity(0.45), radius: 14)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 3)
                .scaleEffect(isTakingPhoto ? 0.87 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.55), value: isTakingPhoto)
        }
        .frame(width: 88, height: 88)
        .onTapGesture { action() }
        .disabled(isTakingPhoto)
    }
}

// MARK: - Pulse Ring

struct PulseRing: View {
    let delay: Double
    let maxScale: CGFloat
    let accent: Color
    @Binding var trigger: Int
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0

    var body: some View {
        Circle()
            .strokeBorder(accent, lineWidth: 1.5)
            .scaleEffect(scale)
            .opacity(opacity)
            .onChange(of: trigger) { _, _ in
                scale = 1.0
                opacity = 0.8
                withAnimation(.easeOut(duration: 0.75).delay(delay)) {
                    scale = maxScale
                    opacity = 0
                }
            }
    }
}

struct DimPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Gallery Thumbnail

struct GalleryThumb: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundColor(Color.white.opacity(0.35))
                    )
            }
        }
        .frame(width: 54, height: 54)
    }
}

// MARK: - Exposure Slider

struct ExposureSlider: View {
    let label: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onRelease: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color(white: 0.4))
                .tracking(1.5)
                .frame(width: 52, alignment: .leading)

            Slider(value: $value, in: range) { editing in
                if !editing { onRelease() }
            }
            .tint(Color(red: 1.0, green: 0.55, blue: 0.1))

            Text(valueText)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 48, alignment: .trailing)
        }
    }
}

// MARK: - Focus Square

struct FocusSquare: View {
    let isLocked: Bool
    @State private var scale: CGFloat = 1.4
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack {
            // Corner brackets instead of full square
            ForEach(0..<4) { i in
                CornerBracket()
                    .stroke(isLocked ? Color.yellow : Color.white, lineWidth: 1.5)
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                scale = 1.0
            }
            if !isLocked {
                withAnimation(.easeOut(duration: 0.6).delay(1.0)) {
                    opacity = 0.4
                }
            }
        }
    }
}

struct CornerBracket: Shape {
    func path(in rect: CGRect) -> Path {
        let len: CGFloat = 12
        var p = Path()
        // Top-left corner
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))
        return p
    }
}

// MARK: - Bar Histogram (8 chunky bars)

struct BarHistogram: View {
    let data: [UInt]
    private let barCount = 8

    private var buckets: [CGFloat] {
        guard !data.isEmpty else { return Array(repeating: 0, count: barCount) }
        let chunkSize = data.count / barCount
        var result = [CGFloat]()
        for i in 0..<barCount {
            let start = i * chunkSize
            let end = min(start + chunkSize, data.count)
            let sum = data[start..<end].reduce(UInt(0), +)
            result.append(CGFloat(sum))
        }
        let maxVal = max(result.max() ?? 1, 1)
        return result.map { $0 / maxVal }
    }

    private let barColors: [Color] = Array(repeating: Color.white, count: 8)

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 3
            let totalSpacing = spacing * CGFloat(barCount - 1)
            let barWidth = (geo.size.width - totalSpacing) / CGFloat(barCount)

            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let h = buckets[i]
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColors[i].opacity(0.85))
                            .frame(
                                width: barWidth,
                                height: max(geo.size.height * h, 2)
                            )
                    }
                }
            }
        }
        .padding(4)
    }
}

// MARK: - Help Sheet

struct HelpSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.05).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Image("AppLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            Text("NO AI. JUST YOUR SENSOR.")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.1))
                                .tracking(2)
                        }
                        Spacer()
                    }
                    .padding(.top, 32)

                    // What it does
                    helpCard(
                        icon: "camera.aperture",
                        title: "WHY RAWCAM",
                        body: "RawCam captures photos as unprocessed RAW DNG files straight from your iPhone's sensor. No Smart HDR, no Deep Fusion, no Night Mode, no AI noise reduction, no sharpening. Open the DNG in Lightroom or Darkroom and you get 2-3 extra stops of recovery the JPEG version never had."
                    )

                    helpCard(
                        icon: "arrow.triangle.branch",
                        title: "RAW vs RAW+JPG",
                        body: "RAW saves a single DNG file. RAW+JPG captures the same frame twice: one clean DNG and one Apple-processed JPEG, saved as two separate photos. Great for comparing what Apple does to your shots."
                    )

                    helpCard(
                        icon: "hand.tap",
                        title: "FOCUS & LOCK",
                        body: "Tap the preview to focus. Long-press to lock both focus and exposure. Tap the yellow AF/AE badge in the panel to unlock."
                    )

                    helpCard(
                        icon: "exclamationmark.triangle",
                        title: "LIMITATIONS",
                        body: "iOS caps third-party RAW at 12MP (Apple locks 48MP to their own camera). Lens correction always runs at the hardware level. These are iOS limitations, not app limitations."
                    )

                    // Credit
                    HStack {
                        Spacer()
                        Text("Made by santiagoalonso.com")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(white: 0.35))
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(white: 0.5))
                            .frame(width: 32, height: 32)
                            .background(Color(white: 0.15), in: Circle())
                    }
                    .padding(16)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func helpCard(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.1))
                .frame(width: 40, height: 40)
                .background(Color(red: 1.0, green: 0.55, blue: 0.1).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .tracking(1.5)
                Text(body)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(Color(white: 0.6))
                    .lineSpacing(3)
            }
        }
        .padding(16)
        .background(Color(red: 0.10, green: 0.10, blue: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Camera Preview

class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}
