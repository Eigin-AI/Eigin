import SwiftData
import SwiftUI

/// Scenes the automated App Store screenshots can stage.
///
/// Staged with `--screenshot-scenario <name>` in the dev app; see
/// `Sources/App/Debug/Screenshots` (compiled into `EiginDev` only).
/// Listing order lives in `EiginUITests/ScreenshotsUITests.swift`, which
/// numbers each capture.
enum ScreenshotScene: String {
    case care
    case onDevice = "on-device"
    case asksFirst = "asks-first"
    case memory
    case followUp = "follow-up"
    case connections
    case modelPicker = "model-picker"
    case intents
    case intentDetail = "intent-detail"
    case skills
    case skillDetail = "skill-detail"
    case spaces
    case spaceDetail = "space-detail"
    case permissions
    case knowledge
}

/// Installs a screenshot scene at launch. The only implementation is
/// `ScreenshotModeInstaller`, which lives in the dev-only screenshot module and
/// is looked up by name — App Store builds never contain it, so this stays a
/// no-op there.
@objc protocol ScreenshotModeInstalling {
    @MainActor static func activate(scenario: String)
}

/// Bridge between the app shell and the dev-only screenshot module. The module
/// stages the scene's root view and seeded store here during app init, before
/// the first frame renders.
@MainActor
enum ScreenshotMode {
    static let scenarioArgument = "--screenshot-scenario"

    /// The scene's root view, replacing the app's normal shell. Nil outside screenshot mode.
    private(set) static var sceneRoot: AnyView?
    /// The seeded in-memory store. Nil outside screenshot mode.
    private(set) static var modelContainer: ModelContainer?

    /// Detects `--screenshot-scenario` and hands the launch to the dev-only installer.
    static func activateIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: scenarioArgument),
              arguments.indices.contains(index + 1)
        else { return }
        guard let installer = NSClassFromString("EiginDev.ScreenshotModeInstaller")
            as? ScreenshotModeInstalling.Type
        else { return }
        installer.activate(scenario: arguments[index + 1])
    }

    /// Called by the screenshot installer to take over the launch.
    static func stage(root: AnyView, container: ModelContainer) {
        sceneRoot = root
        modelContainer = container
    }
}
