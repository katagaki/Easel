import XCTest

/// Stages and captures the App Store screenshots.
///
/// Driven by `Assets/App Store/capture.sh`, which seeds the documents these
/// open and says where to write through `SCREENSHOT_DIR` and which language to
/// use through `SCREENSHOT_LANGUAGE`. Without them the tests skip, so they stay
/// out of the way of an ordinary test run.
final class AppStoreScreenshots: XCTestCase {
    /// What is set up over the picture before the capture.
    private enum Stage {
        /// Just the canvas, with the brush in hand.
        case canvas
        case layers
        /// The brush settings popover, with the chalk tip picked.
        case brushSettings
        /// The filters on the named layer, keyed by language.
        case filters(layer: [String: String])
        /// The top layer's points, handles and text, ready to edit.
        case points
        case adjustments
    }

    private struct Shot {
        let name: String
        /// The file name without its extension, keyed by language.
        let document: [String: String]
        let stage: Stage
        /// Which of the picture's own swatches to paint with, if not black.
        var swatch: Int?
        var isDark = false
    }

    private static let lakeside = ["en": "Lakeside Evening", "ja": "湖畔の夕暮れ"]
    private static let poppies = ["en": "Poppy Study", "ja": "ポピーの習作"]
    private static let poster = ["en": "Summer Festival", "ja": "夏まつり"]

    private static let shots = [
        Shot(name: "01-paint", document: lakeside, stage: .canvas, swatch: 0),
        Shot(name: "02-layers", document: lakeside, stage: .layers),
        Shot(name: "03-brushes", document: poppies, stage: .brushSettings, swatch: 0),
        Shot(name: "04-filters", document: lakeside, stage: .filters(layer: ["en": "Sky", "ja": "空"])),
        Shot(name: "05-design", document: poster, stage: .points),
        Shot(name: "06-dark", document: poppies, stage: .adjustments, swatch: 1, isDark: true),
    ]

    private var directory: URL!
    private var language = "en"
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["SCREENSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("run through Assets/App Store/capture.sh")
        }
        directory = URL(fileURLWithPath: path)
        language = environment["SCREENSHOT_LANGUAGE"] ?? "en"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func testScreens() throws {
        defer { XCUIDevice.shared.appearance = .light }
        XCUIDevice.shared.orientation = .portrait
        for shot in Self.shots {
            let appearance: XCUIDevice.Appearance = shot.isDark ? .dark : .light
            if XCUIDevice.shared.appearance != appearance {
                XCUIDevice.shared.appearance = appearance
                // The switch takes a moment to reach the system.
                Thread.sleep(forTimeInterval: 3)
            }
            launch()
            open(try XCTUnwrap(shot.document[language]))
            if let swatch = shot.swatch { pickSwatch(swatch) }
            try stage(shot.stage)
            // Let the panels finish animating in.
            Thread.sleep(forTimeInterval: 2)
            let file = directory.appendingPathComponent("\(shot.name).png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: file)
        }
    }

    // MARK: - Steps

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func launch() {
        app = XCUIApplication()
        let locale = language == "ja" ? "ja_JP" : "en_US"
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
    }

    /// Opens a document from the app's folder in the document browser.
    private func open(_ name: String) {
        let browse = app.buttons[language == "ja" ? "ブラウズ" : "Browse"].firstMatch
        if browse.waitForExistence(timeout: 15), !browse.isSelected {
            browse.tap()
        }

        // The cell, not its name: a tap on the name label does not open the file.
        let file = app.collectionViews.cells.containing(.staticText, identifier: name).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10), "\(name) is not in the browser")
        // On iPhone the browser starts as a sheet that only shows its first row.
        if !file.isHittable {
            app.collectionViews.firstMatch.swipeUp()
        }
        file.tap()

        let canvas = app.descendants(matching: .any).matching(identifier: "canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 20), "\(name) never opened")
        Thread.sleep(forTimeInterval: 1)
    }

    private func stage(_ stage: Stage) throws {
        switch stage {
        case .canvas:
            // The iPad opens with the layers in an inspector; put away, the
            // picture has the screen.
            if isPad { tap("toggleInspector") }
        case .layers:
            // The iPad already shows them in its inspector.
            if !isPad { tap("panel.layers") }
        case .brushSettings:
            let label = language == "ja" ? "ブラシ設定" : "Brush Settings"
            let button = app.buttons[label].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "missing the brush settings button")
            button.tap()
            let tip = app.descendants(matching: .any).matching(identifier: "brushTip").firstMatch
            XCTAssertTrue(tip.waitForExistence(timeout: 5), "missing the tip picker")
            tip.tap()
            let chalk = app.buttons[language == "ja" ? "チョーク" : "Chalk"].firstMatch
            XCTAssertTrue(chalk.waitForExistence(timeout: 5), "missing the chalk tip")
            chalk.tap()
        case .filters(let layer):
            if !isPad { tap("panel.layers") }
            tapInList("layer.\(try XCTUnwrap(layer[language]))")
            tapInList("layerFilters")
        case .points:
            tap("tool.nodes")
        case .adjustments:
            tap("panel.adjustments")
        }
    }

    /// Picks one of the picture's own swatches from the colour well, then
    /// puts the swatches away with a tap outside them, which only closes the
    /// popover: nothing is painted where it lands.
    private func pickSwatch(_ index: Int) {
        tap("colorWell")
        let swatches = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '#'"))
        XCTAssertTrue(swatches.firstMatch.waitForExistence(timeout: 5), "missing the swatches")
        swatches.element(boundBy: index).tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        Thread.sleep(forTimeInterval: 1)
    }

    /// Taps a row of a panel's list, scrolling the list up to it first: the
    /// rows below the fold are not made until they are scrolled to.
    private func tapInList(_ identifier: String) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let list = app.collectionViews.firstMatch
        for _ in 0..<6 where list.exists && !(element.exists && element.isHittable) {
            list.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "missing \(identifier)")
        element.tap()
    }

    /// Taps the element with `identifier`, scrolling the tool carousel along
    /// first if the element is off the end of it.
    private func tap(_ identifier: String) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), "missing \(identifier)")
        // Off the end of the carousel, a button has no point to tap, so
        // where it sits is checked rather than whether it can be hit.
        for _ in 0..<3 where !app.frame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)) {
            app.scrollViews.containing(.button, identifier: "tool.brush").firstMatch.swipeLeft()
        }
        element.tap()
    }
}
