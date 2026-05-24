import SwiftUI
import AVFoundation
import CoreMotion
import MediaPlayer

// MARK: - Theme

private enum Theme {
    static let bg          = Color(red: 0.04, green: 0.04, blue: 0.04)
    static let panel       = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let surface     = Color(red: 0.12, green: 0.12, blue: 0.12)
    static let surfaceHigh = Color(red: 0.18, green: 0.18, blue: 0.18)
    static let accent      = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let accentHot   = Color(red: 1.0, green: 0.82, blue: 0.28)
    static let accentCov   = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let textPrimary   = Color.white
    static let textSecondary = Color(white: 0.55)
    static let textTertiary  = Color(white: 0.30)

    static let tapSpring = Animation.spring(response: 0.28, dampingFraction: 0.62)
}

// MARK: - Camera View

struct CameraView: View {
    private enum ControlPanel {
        case exposure
        case whiteBalance
        case lens
    }

    private enum TapTarget {
        case focus
        case meter
    }

    @StateObject private var camera = CameraManager()
    @StateObject private var level = LevelManager()
    @StateObject private var volumeButtons = VolumeButtonObserver()
    @State private var showPermissionDenied = false
    @State private var viewSize: CGSize = .zero

    // Panel state
    @State private var showHelp = false
    @State private var activePanel: ControlPanel?
    @AppStorage("tapTarget") private var tapTargetRaw = "focus"
    @AppStorage("showGrid") private var showGrid = false
    @AppStorage("showLevel") private var showLevel = false
    @AppStorage("selfTimerSeconds") private var selfTimerSeconds = 0
    @AppStorage("antiShakeEnabled") private var antiShakeEnabled = false
    @AppStorage("bracketEnabled") private var bracketEnabled = false
    @AppStorage("captureMode") private var persistedCaptureMode = CaptureMode.raw.rawValue
    @State private var controlsExpanded = false
    @State private var countdown: Int?
    @State private var waitingForSteadyShot = false
    @State private var showLastDetails = false

    // Shutter animation
    @State private var shutterPulse = 0
    @State private var flashOverlay = false

    private let hapticMedium = UIImpactFeedbackGenerator(style: .medium)
    private let hapticHeavy  = UIImpactFeedbackGenerator(style: .heavy)

    private var tapTarget: TapTarget {
        get { tapTargetRaw == "meter" ? .meter : .focus }
        nonmutating set { tapTargetRaw = newValue == .meter ? "meter" : "focus" }
    }

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

            if showGrid {
                GridOverlay(bottomInset: controlsExpanded ? 360 : 220)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if showLevel {
                HorizonLevel(roll: level.roll)
                    .padding(.bottom, controlsExpanded ? 220 : 150)
                    .allowsHitTesting(false)
            }

            if camera.isHighlightClipping {
                ZebraOverlay(bottomInset: controlsExpanded ? 360 : 220)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

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

            if camera.showExposureIndicator, let pt = camera.exposurePoint {
                ExposureTarget()
                    .position(pt)
            }

            if let countdown {
                CountdownOverlay(value: countdown)
                    .allowsHitTesting(false)
            }

            if waitingForSteadyShot {
                SteadyShotOverlay(score: level.motionScore)
                    .allowsHitTesting(false)
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

            VolumeButtonCaptureView()
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.08), value: flashOverlay)
        .animation(Theme.tapSpring, value: camera.showFocusIndicator)
        .preferredColorScheme(.dark)
        .onAppear {
            hapticMedium.prepare()
            hapticHeavy.prepare()
            level.start()
            camera.captureMode = CaptureMode(rawValue: persistedCaptureMode) ?? .raw
            volumeButtons.start()
            checkPermissionAndStart()
        }
        .onDisappear {
            level.stop()
            volumeButtons.stop()
        }
        .onChange(of: camera.captureMode) { _, mode in
            persistedCaptureMode = mode.rawValue
        }
        .onReceive(volumeButtons.$pressCount.dropFirst()) { _ in
            guard volumeButtons.isListening else { return }
            hapticHeavy.impactOccurred()
            hapticHeavy.prepare()
            triggerCapture()
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
        .sheet(isPresented: $showLastDetails) {
            LastCaptureSheet(details: camera.lastCaptureDetails, image: camera.lastThumbnail)
        }
    }

    // MARK: - Focus Gestures

    private var focusGestures: some Gesture {
        SimultaneousGesture(
            SpatialTapGesture().onEnded { v in
                hapticMedium.impactOccurred()
                hapticMedium.prepare()
                if tapTarget == .meter {
                    camera.meterExposure(at: v.location, in: viewSize)
                } else {
                    camera.focus(at: v.location, in: viewSize)
                }
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
            histogramCluster
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

    private var histogramCluster: some View {
        HStack(spacing: 6) {
            BarHistogram(
                data: camera.histogramData,
                shadowClipping: camera.isShadowClipping,
                highlightClipping: camera.isHighlightClipping
            )
            .frame(width: 56, height: 28)

            if camera.isShadowClipping || camera.isHighlightClipping {
                Text("CLIP")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .tracking(0.8)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.accent, in: Capsule())
                    .shadow(color: Theme.accent.opacity(0.4), radius: 10)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.black.opacity(0.36), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
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
            .background(.black.opacity(0.38), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
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
            } else {
                ExposureSlider(
                    label: "EV",
                    valueText: evLabel(camera.exposureBias),
                    value: Binding(
                        get: { Double(camera.exposureBias) },
                        set: { camera.exposureBias = Float($0) }
                    ),
                    range: Double(camera.minExposureBias)...Double(camera.maxExposureBias),
                    onRelease: { camera.setExposureBias(camera.exposureBias) }
                )
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 8)
    }

    private func evLabel(_ value: Float) -> String {
        if abs(value) < 0.05 { return "0.0" }
        return String(format: "%+.1f", value)
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
                        .background(ControlChipBackground(isActive: camera.whiteBalancePreset == preset))
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
            if let details = camera.lastCaptureDetails {
                LastCaptureStrip(details: details) {
                    showLastDetails = true
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if controlsExpanded {
                controlsDrawer
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .simultaneousGesture(controlsRevealGesture)
                    .animation(Theme.tapSpring, value: controlsExpanded)
            }

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
                // Left — gallery + tools, fills equal half
                HStack(spacing: 12) {
                    Button {
                        if let url = URL(string: "photos-redirect://") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        GalleryThumb(image: camera.lastThumbnail)
                    }
                    .buttonStyle(DimPressStyle())

                    controlsToggleButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Center — shutter, fixed width keeps it screen-centered
                ShutterButton(
                    mode: camera.captureMode,
                    isTakingPhoto: camera.isTakingPhoto || countdown != nil || waitingForSteadyShot,
                    pulseCount: $shutterPulse
                ) {
                    hapticHeavy.impactOccurred()
                    hapticHeavy.prepare()
                    triggerCapture()
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
            .simultaneousGesture(controlsRevealGesture)
        }
    }

    private var controlsToggleButton: some View {
        Button {
            hapticMedium.impactOccurred()
            hapticMedium.prepare()
            withAnimation(Theme.tapSpring) {
                controlsExpanded.toggle()
                if !controlsExpanded {
                    activePanel = nil
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: controlsExpanded ? "slider.horizontal.3" : "slider.horizontal.3")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(controlsExpanded ? Theme.bg : Theme.accent)
                    .frame(width: 52, height: 52)
                    .background(ControlChipBackground(isActive: controlsExpanded))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: controlsExpanded ? Theme.accent.opacity(0.28) : .black.opacity(0.26), radius: 10, y: 4)
                    .contentShape(Rectangle())

                if activeToolDots.contains(true) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1))
                        .offset(x: -5, y: 5)
                }
            }
        }
        .buttonStyle(DimPressStyle())
        .accessibilityLabel(controlsExpanded ? "Hide controls" : "Show controls")
    }

    private var controlsDrawer: some View {
        VStack(spacing: 0) {
            controlStrip

            if activePanel == .exposure {
                exposurePanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if activePanel == .whiteBalance {
                wbPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if activePanel == .lens {
                lensPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.78),
                    Theme.panel.opacity(0.82),
                    Color.black.opacity(0.64)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
        .shadow(color: Theme.accent.opacity(0.10), radius: 22)
        .animation(Theme.tapSpring, value: activePanel)
    }

    private var controlStrip: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                controlChip(
                    icon: "plusminus",
                    title: "EXP",
                    value: exposureSummary,
                    isActive: activePanel == .exposure,
                    action: { togglePanel(.exposure) }
                )

                controlChip(
                    icon: "thermometer.medium",
                    title: "WB",
                    value: whiteBalanceSummary,
                    isActive: activePanel == .whiteBalance,
                    action: { togglePanel(.whiteBalance) }
                )

                controlChip(
                    icon: "camera.aperture",
                    title: "LENS",
                    value: activeLensSummary,
                    isActive: activePanel == .lens,
                    action: { togglePanel(.lens) }
                )

                focusLockChip
            }

            HStack(spacing: 8) {
                controlChip(
                    icon: "timer",
                    title: "TIMER",
                    value: timerSummary,
                    isActive: selfTimerSeconds > 0,
                    action: { cycleTimer() }
                )

                controlChip(
                    icon: "grid",
                    title: "GRID",
                    value: showGrid ? "ON" : "OFF",
                    isActive: showGrid,
                    action: { showGrid.toggle() }
                )

                controlChip(
                    icon: "level",
                    title: "LEVEL",
                    value: showLevel ? "ON" : "OFF",
                    isActive: showLevel,
                    action: { showLevel.toggle() }
                )

                controlChip(
                    icon: tapTarget == .meter ? "scope" : "viewfinder",
                    title: "TAP",
                    value: tapTarget == .meter ? "METER" : "FOCUS",
                    isActive: tapTarget == .meter,
                    action: { tapTarget = tapTarget == .focus ? .meter : .focus }
                )
            }

            HStack(spacing: 8) {
                controlChip(
                    icon: "hand.raised",
                    title: "SHAKE",
                    value: antiShakeEnabled ? "ON" : "OFF",
                    isActive: antiShakeEnabled,
                    action: { antiShakeEnabled.toggle() }
                )

                controlChip(
                    icon: "square.stack.3d.down.right",
                    title: "BRKT",
                    value: bracketEnabled ? "3 RAW" : "OFF",
                    isActive: bracketEnabled,
                    action: { bracketEnabled.toggle() }
                )

                controlChip(
                    icon: "info.square",
                    title: "LAST",
                    value: camera.lastCaptureDetails == nil ? "NONE" : "VIEW",
                    isActive: showLastDetails,
                    action: {
                        if camera.lastCaptureDetails == nil {
                            camera.errorMessage = "No capture details yet"
                        } else {
                            showLastDetails = true
                        }
                    }
                )

                controlChip(
                    icon: "speaker.wave.2",
                    title: "VOL",
                    value: "SHUT",
                    isActive: false,
                    action: { camera.errorMessage = "Volume buttons trigger shutter" }
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var lensPanel: some View {
        VStack(spacing: 12) {
            Divider().background(Theme.surfaceHigh).padding(.horizontal, 16)

            HStack(spacing: 8) {
                ForEach(camera.availableLenses) { lens in
                    let isSelected = camera.selectedLensID == lens.id
                    Button {
                        hapticMedium.impactOccurred()
                        hapticMedium.prepare()
                        camera.switchLens(to: lens)
                    } label: {
                        VStack(spacing: 3) {
                            Text(lens.label)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                            Text(isSelected ? (lens.rawSupported ? "RAW" : "NO RAW") : "CHECK")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.8)
                        }
                        .foregroundColor(isSelected ? Theme.bg : Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(ControlChipBackground(isActive: isSelected))
                    }
                    .buttonStyle(DimPressStyle())
                }
            }
            .padding(.horizontal, 20)

            if camera.availableLenses.isEmpty {
                Text("Lens selection appears on devices with multiple rear cameras.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 8)
    }

    private var focusLockChip: some View {
        Button {
            guard camera.isFocusLocked || camera.isExposureLocked else { return }
            hapticMedium.impactOccurred()
            hapticMedium.prepare()
            camera.unlockFocus()
        } label: {
            let isLocked = camera.isFocusLocked || camera.isExposureLocked
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: isLocked ? "lock.fill" : "viewfinder")
                        .font(.system(size: 10, weight: .bold))
                    Text("AF/AE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.9)
                }
                Text(camera.isFocusLocked || camera.isExposureLocked ? "LOCK" : "AUTO")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            .foregroundColor(isLocked ? Theme.bg : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                ControlChipBackground(isActive: isLocked)
            )
            .shadow(color: isLocked ? Theme.accent.opacity(0.28) : .black.opacity(0.22), radius: isLocked ? 10 : 5, y: isLocked ? 0 : 3)
        }
        .buttonStyle(DimPressStyle())
        .disabled(!(camera.isFocusLocked || camera.isExposureLocked))
    }

    private func controlChip(
        icon: String,
        title: String,
        value: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            hapticMedium.impactOccurred()
            hapticMedium.prepare()
            action()
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                    Text(title)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.9)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(isActive ? Theme.bg : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                ControlChipBackground(isActive: isActive)
            )
            .shadow(color: isActive ? Theme.accent.opacity(0.28) : .black.opacity(0.22), radius: isActive ? 10 : 5, y: isActive ? 0 : 3)
        }
        .buttonStyle(DimPressStyle())
    }

    private var exposureSummary: String {
        camera.isManualExposure ? shutterLabel : evLabel(camera.exposureBias)
    }

    private var whiteBalanceSummary: String {
        if camera.isManualWhiteBalance {
            return "\(Int(camera.kelvin))K"
        }
        return "AUTO"
    }

    private var activeLensSummary: String {
        camera.availableLenses.first { $0.id == camera.selectedLensID }?.label ?? "1x"
    }

    private func togglePanel(_ panel: ControlPanel) {
        withAnimation(Theme.tapSpring) {
            controlsExpanded = true
            activePanel = activePanel == panel ? nil : panel
        }
    }

    private var controlsRevealGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                if value.translation.height < -24 {
                    hapticMedium.impactOccurred()
                    hapticMedium.prepare()
                    withAnimation(Theme.tapSpring) {
                        controlsExpanded = true
                    }
                } else if value.translation.height > 24 {
                    hapticMedium.impactOccurred()
                    hapticMedium.prepare()
                    withAnimation(Theme.tapSpring) {
                        controlsExpanded = false
                        activePanel = nil
                    }
                }
            }
    }

    private var activeToolDots: [Bool] {
        [
            selfTimerSeconds > 0,
            showGrid || showLevel,
            tapTarget == .meter,
            antiShakeEnabled || bracketEnabled
        ]
    }

    private var timerSummary: String {
        selfTimerSeconds == 0 ? "OFF" : "\(selfTimerSeconds)S"
    }

    private func cycleTimer() {
        switch selfTimerSeconds {
        case 0: selfTimerSeconds = 3
        case 3: selfTimerSeconds = 10
        default: selfTimerSeconds = 0
        }
    }

    // MARK: - Helpers

    private func triggerCapture() {
        if countdown != nil {
            countdown = nil
            return
        }

        guard selfTimerSeconds > 0 else {
            triggerSteadyOrCapture()
            return
        }

        runCountdown(selfTimerSeconds)
    }

    private func runCountdown(_ value: Int) {
        guard value > 0 else {
            countdown = nil
            triggerSteadyOrCapture()
            return
        }

        countdown = value
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard countdown == value else { return }
            runCountdown(value - 1)
        }
    }

    private func triggerSteadyOrCapture() {
        guard antiShakeEnabled else {
            performCapture()
            return
        }

        waitingForSteadyShot = true
        waitForSteadyShot(attempt: 0)
    }

    private func waitForSteadyShot(attempt: Int) {
        guard waitingForSteadyShot else { return }

        if level.isSteady || attempt >= 20 {
            waitingForSteadyShot = false
            performCapture()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            waitForSteadyShot(attempt: attempt + 1)
        }
    }

    private func performCapture() {
        triggerFlash()
        camera.capturePhoto(bracketed: bracketEnabled)
    }

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

    private let accent: Color = Theme.accent

    var body: some View {
        ZStack {
            // Ambient glow
            Circle()
                .fill(RadialGradient(
                    colors: [accent.opacity(0.26), accent.opacity(0.08), Color.clear],
                    center: .center, startRadius: 10, endRadius: 55
                ))
                .frame(width: 118, height: 118)

            // Pulse rings
            PulseRing(delay: 0,    maxScale: 1.9, accent: accent, trigger: $pulseCount)
                .frame(width: 72, height: 72)
            PulseRing(delay: 0.12, maxScale: 2.3, accent: accent, trigger: $pulseCount)
                .frame(width: 72, height: 72)

            // Outer ring
            Circle()
                .strokeBorder(accent.opacity(0.55), lineWidth: 1.5)
                .frame(width: 82, height: 82)

            Circle()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 7)
                .frame(width: 76, height: 76)

            // Button body
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white, accent.opacity(0.96), accent.opacity(0.82)],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: 46
                    )
                )
                .frame(width: 68, height: 68)
                .shadow(color: accent.opacity(0.45), radius: 14)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 3)
                .scaleEffect(isTakingPhoto ? 0.87 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.55), value: isTakingPhoto)

            Image(systemName: mode == .coverage ? "plus" : "circle.fill")
                .font(.system(size: mode == .coverage ? 16 : 8, weight: .bold))
                .foregroundColor(.black.opacity(0.56))
                .scaleEffect(isTakingPhoto ? 0.5 : 1)
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

struct ControlChipBackground: View {
    let isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(
                LinearGradient(
                    colors: isActive
                        ? [Theme.accentHot, Theme.accent]
                        : [Theme.surfaceHigh.opacity(0.72), Theme.surface.opacity(0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.white.opacity(0.34) : Color.white.opacity(0.07),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(isActive ? 0.18 : 0.05), lineWidth: 1)
                    .blur(radius: 0.5)
                    .offset(x: 0.5, y: 0.5)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
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
            .tint(Theme.accent)

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

struct ExposureTarget: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.yellow, lineWidth: 1.6)
                .frame(width: 54, height: 54)
            Circle()
                .fill(Color.yellow)
                .frame(width: 5, height: 5)
            Text("AE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.yellow, in: Capsule())
                .offset(y: 36)
        }
        .shadow(color: .black.opacity(0.45), radius: 3)
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
    let shadowClipping: Bool
    let highlightClipping: Bool
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
                            .fill(barColor(for: i).opacity(0.88))
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

    private func barColor(for index: Int) -> Color {
        if index == 0 && shadowClipping { return .yellow }
        if index == barCount - 1 && highlightClipping { return .yellow }
        return .white
    }
}

// MARK: - Capture Aids

struct GridOverlay: View {
    let bottomInset: CGFloat

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let guideHeight = max(geo.size.height - bottomInset, geo.size.height * 0.45)
                let thirdWidth = geo.size.width / 3
                let thirdHeight = guideHeight / 3

                for index in 1...2 {
                    let x = CGFloat(index) * thirdWidth
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: guideHeight))

                    let y = CGFloat(index) * thirdHeight
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.26), lineWidth: 0.8)
        }
    }
}

struct ZebraOverlay: View {
    let bottomInset: CGFloat

    var body: some View {
        GeometryReader { geo in
            let guideHeight = max(geo.size.height - bottomInset, geo.size.height * 0.45)

            Path { path in
                let spacing: CGFloat = 18
                for offset in stride(from: -geo.size.height, through: geo.size.width, by: spacing) {
                    path.move(to: CGPoint(x: offset, y: 0))
                    path.addLine(to: CGPoint(x: offset + guideHeight, y: guideHeight))
                }
            }
            .stroke(Color.yellow.opacity(0.34), lineWidth: 2)
            .frame(width: geo.size.width, height: guideHeight, alignment: .top)
            .clipped()
        }
    }
}

struct HorizonLevel: View {
    let roll: Double

    private var degrees: Double {
        roll * 180 / .pi
    }

    private var isLevel: Bool {
        abs(degrees) < 1.0
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 96, height: 1)

                Rectangle()
                    .fill(isLevel ? Color.green : Color.yellow)
                    .frame(width: 68, height: 2)
                    .rotationEffect(.radians(-roll))
                    .shadow(color: .black.opacity(0.45), radius: 3)
            }

            Text(String(format: "%+.0f°", degrees))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(isLevel ? .green : .white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.48), in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct CountdownOverlay: View {
    let value: Int

    var body: some View {
        Text("\(value)")
            .font(.system(size: 88, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.55), radius: 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct SteadyShotOverlay: View {
    let score: Double

    var body: some View {
        VStack(spacing: 10) {
            ProgressView(value: min(max(1.0 - score * 8, 0), 1))
                .progressViewStyle(.linear)
                .tint(.yellow)
                .frame(width: 130)

            Text("HOLD STEADY")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.yellow, in: Capsule())
        }
        .padding(16)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct LastCaptureSheet: View {
    @Environment(\.dismiss) var dismiss
    let details: CaptureDetails?
    let image: UIImage?

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.05).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("LAST CAPTURE")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .tracking(1.8)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(white: 0.55))
                            .frame(width: 32, height: 32)
                            .background(Color(white: 0.15), in: Circle())
                    }
                }

                if let details {
                    LastCapturePreview(image: image)

                    VStack(spacing: 10) {
                        detailRow("MODE", details.mode)
                        detailRow("LENS", details.lens)
                        detailRow("ISO", "\(details.iso)")
                        detailRow("SHUTTER", details.shutter)
                        detailRow("EV", details.ev)
                        detailRow("WB", details.whiteBalance)
                        detailRow("CLIP", details.clipping)
                    }
                } else {
                    Text("No saved capture yet.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Color(white: 0.7))
                }

                Spacer()
            }
            .padding(22)
        }
        .preferredColorScheme(.dark)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Color(white: 0.42))
                .tracking(1.4)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct LastCapturePreview: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 230)
                    .clipped()
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(Color(white: 0.55))
                    Text("PREVIEW UNAVAILABLE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.48))
                        .tracking(1.4)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .background(Color(white: 0.08))
            }

            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.36)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 12)
    }
}

struct LastCaptureStrip: View {
    let details: CaptureDetails
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.green)

                Text(details.mode)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .tracking(0.8)

                Divider()
                    .frame(height: 14)
                    .background(Color.white.opacity(0.18))

                Text(details.lens)
                Text("ISO \(details.iso)")
                Text(details.shutter)
                Text("EV \(details.ev)")

                Spacer(minLength: 0)

                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(white: 0.55))
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(Color(white: 0.70))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(DimPressStyle())
    }
}

final class LevelManager: ObservableObject {
    @Published var roll: Double = 0
    @Published var motionScore: Double = 1

    private let motionManager = CMMotionManager()

    var isSteady: Bool {
        motionScore < 0.08
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            self?.roll = motion.attitude.roll

            let rotation = motion.rotationRate
            let acceleration = motion.userAcceleration
            let rotationMagnitude = abs(rotation.x) + abs(rotation.y) + abs(rotation.z)
            let accelerationMagnitude = abs(acceleration.x) + abs(acceleration.y) + abs(acceleration.z)
            self?.motionScore = rotationMagnitude * 0.22 + accelerationMagnitude
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}

final class VolumeButtonObserver: ObservableObject {
    @Published var pressCount = 0
    @Published var isListening = false

    private var observation: NSKeyValueObservation?
    private var baselineVolume: Float?

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)
        baselineVolume = session.outputVolume
        isListening = true

        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            guard let self, self.isListening else { return }
            let current = session.outputVolume
            guard let baseline = self.baselineVolume else {
                self.baselineVolume = current
                return
            }

            guard abs(current - baseline) > 0.01 else { return }

            DispatchQueue.main.async {
                self.baselineVolume = current
                self.pressCount += 1
            }
        }
    }

    func stop() {
        isListening = false
        observation?.invalidate()
        observation = nil
    }
}

struct VolumeButtonCaptureView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsVolumeSlider = true
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
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
                        body: "RawCam saves RAW DNG files from the sensor path before Apple's normal photo pipeline bakes in sharpening, denoising, tone mapping, Smart HDR, or Deep Fusion. Edit the DNG later in Lightroom, Darkroom, Capture One, or another RAW editor."
                    )

                    helpCard(
                        icon: "arrow.triangle.branch",
                        title: "RAW vs RAW+JPG",
                        body: "RAW saves one DNG. RAW+JPG saves a DNG and an Apple-processed JPEG as separate photos, so you can compare the untouched file against the phone's finished version."
                    )

                    helpCard(
                        icon: "hand.tap",
                        title: "FOCUS & METER",
                        body: "Tap the preview to focus. Long-press to lock focus only. Switch TAP to METER when you want taps to set exposure instead. The yellow AE target shows the metering point."
                    )

                    helpCard(
                        icon: "line.3.horizontal.decrease",
                        title: "HISTOGRAM & ZEBRA",
                        body: "The top-left histogram shows shadows on the left and highlights on the right. If highlights clip, RawCam shows CLIP and yellow zebra stripes over the preview area."
                    )

                    helpCard(
                        icon: "camera.filters",
                        title: "LENS & EXPOSURE",
                        body: "Use LENS to switch supported rear cameras. EXP gives you EV control in auto mode, or ISO and shutter when manual exposure is enabled. WB controls white balance presets and Kelvin."
                    )

                    helpCard(
                        icon: "timer",
                        title: "CAPTURE AIDS",
                        body: "Tap the control icon next to the photo thumbnail to show or hide the full panel. You can also swipe up to reveal controls and swipe down to hide them. GRID and LEVEL help composition. TIMER gives you 3s or 10s delay. SHAKE waits briefly for steadier hands. BRKT saves three RAW frames at different EV values."
                    )

                    helpCard(
                        icon: "speaker.wave.2",
                        title: "SHUTTER SHORTCUTS",
                        body: "Tap the shutter or use the iPhone volume buttons. RawCam also exposes an Open Camera shortcut for Shortcuts, Siri, Spotlight, and Action Button workflows."
                    )

                    helpCard(
                        icon: "exclamationmark.triangle",
                        title: "LIMITATIONS",
                        body: "iOS caps third-party RAW capture at 12MP. Apple's own Camera app keeps exclusive access to the full 48MP RAW path. Lens correction can also happen at the hardware level."
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
