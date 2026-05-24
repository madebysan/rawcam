import AppIntents

struct OpenRawCamIntent: AppIntent {
    static var title: LocalizedStringResource = "Open RawCam"
    static var description = IntentDescription("Open RawCam directly to the camera.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct RawCamShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenRawCamIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Open camera in \(.applicationName)",
                "Start \(.applicationName)"
            ],
            shortTitle: "Open Camera",
            systemImageName: "camera.aperture"
        )
    }
}
