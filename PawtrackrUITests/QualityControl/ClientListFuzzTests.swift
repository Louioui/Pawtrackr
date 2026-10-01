import XCTest

/// Seeded random UI actions on the heavy-load client book (600 hostile
/// clients plus the poisoned ones): taps and double taps on cards, fast
/// search input, flick scrolls, filter and sort changes, the New Client
/// sheet, Back, full and cancelled swipe backs. After every action the app
/// must still be in the foreground and answering, with at most one sheet
/// up; every few actions it must find its way back to the list.
///
/// Slow by design (500 actions): run it locally, not in CI. A failure names
/// the seed and the last actions; re-run one with PAWTRACKR_FUZZ_SEED.
@MainActor
final class ClientListFuzzTests: QualityControlUITestCase {
    private enum Action: CaseIterable {
        case tapCard, doubleTapCard, typeSearch, clearSearch, scroll, filter, sort
        case openNewClientSheet, back, swipeBack, cancelledSwipeBack
    }

    private let fragments = ["maria", "LO", "🐶", "محمد", "zz", "de la", "312", "ß", "Stress", "x"]
    private let filters = ["All", "Active", "Needs Attention", "Missing Info"]
    private let sorts = ["Last Name", "First Name", "Pet's Name", "Last Visit", "Newest"]

    override func setUpWithError() throws {
        try super.setUpWithError()
        launch(startTab: "clients", scenario: "heavy_load")
        XCTAssertTrue(waitForClientsScreen(timeout: 30), "Clients screen did not load with the heavy-load book.")
    }

    func testFiveHundredRandomActionsLeaveTheAppResponsive() throws {
        let environment = ProcessInfo.processInfo.environment
        let seed = environment["PAWTRACKR_FUZZ_SEED"].flatMap(UInt64.init) ?? 0xF022
        let actions = environment["PAWTRACKR_FUZZ_ACTIONS"].flatMap(Int.init) ?? 500
        var rng = FuzzRandom(seed: seed)
        var log: [String] = []

        for step in 0..<actions {
            let action = Action.allCases[rng.next(below: Action.allCases.count)]
            log.append(perform(action, rng: &rng))

            let context = "seed \(seed), step \(step): \(log.suffix(8).joined(separator: " → "))"
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "App left the foreground (\(context))")
            XCTAssertLessThanOrEqual(newClientSheetCount, 1, "Two New Client sheets at once (\(context))")
            if step.isMultiple(of: 25) {
                XCTAssertTrue(returnToList(), "Couldn't get back to the list (\(context))")
            }
        }
        XCTAssertTrue(returnToList(), "Couldn't get back to the list at the end.")
    }

    /// Scroll hitches on the heavy-load book. Run on a 120 Hz device for the
    /// number that matters; Xcode records the baseline per device.
    func testScrollHitchesOnTheHeavyBook() throws {
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]

        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            scroll.swipeUp(velocity: .fast)
            stopMeasuring()
            scroll.swipeDown(velocity: .fast)
        }
    }

    // MARK: - Actions

    private func perform(_ action: Action, rng: inout FuzzRandom) -> String {
        switch action {
        case .tapCard, .doubleTapCard:
            let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'clients.row.'"))
            let visible = min(cards.count, 6)
            guard visible > 0 else { return "no card" }
            let card = cards.element(boundBy: rng.next(below: visible))
            guard card.isHittable else { return "card off screen" }
            if action == .doubleTapCard { card.doubleTap() } else { card.tap() }
            return action == .doubleTapCard ? "double tap card" : "tap card"

        case .typeSearch:
            let field = app.searchFields.firstMatch
            guard field.exists, field.isHittable else { return "no search field" }
            field.tap()
            field.typeText(fragments[rng.next(below: fragments.count)])
            return "type"

        case .clearSearch:
            let clear = app.searchFields.firstMatch.buttons["Clear text"]
            guard clear.exists, clear.isHittable else { return "nothing to clear" }
            clear.tap()
            return "clear search"

        case .scroll:
            let scroll = app.scrollViews.firstMatch
            guard scroll.exists else { return "no scroll" }
            if rng.next(below: 2) == 0 {
                scroll.swipeUp(velocity: .fast)
            } else {
                scroll.swipeDown(velocity: .fast)
            }
            return "scroll"

        case .filter:
            let name = filters[rng.next(below: filters.count)]
            return tapIfHittable(app.buttons[name]) ? "filter \(name)" : "filter unreachable"

        case .sort:
            guard tapIfHittable(app.buttons["clients.sortMenu.inline"]) else { return "sort unreachable" }
            let name = sorts[rng.next(below: sorts.count)]
            if !tapIfHittable(app.buttons[name], timeout: 2) {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap() // dismiss the menu
            }
            return "sort \(name)"

        case .openNewClientSheet:
            let add = app.buttons["clients.fab.addClient"]
            guard tapIfHittable(add) else { return "add unreachable" }
            if app.textFields["newClient.firstName"].waitForExistence(timeout: 4) {
                _ = tapIfHittable(app.buttons["Cancel"], timeout: 2)
            }
            return "new client sheet"

        case .back:
            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard app.buttons["clientDetail.editInline"].exists, back.exists, back.isHittable else { return "no back" }
            back.tap()
            return "back"

        case .swipeBack, .cancelledSwipeBack:
            guard app.buttons["clientDetail.editInline"].exists else { return "no screen to swipe" }
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            let full = action == .swipeBack
            edge.press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: full ? 0.9 : 0.3, dy: 0.5)),
                withVelocity: full ? .fast : .slow,
                thenHoldForDuration: full ? 0 : 0.3
            )
            return full ? "swipe back" : "cancelled swipe back"
        }
    }

    private var newClientSheetCount: Int {
        app.textFields.matching(identifier: "newClient.firstName").count
    }

    /// Back out of any sheet and screen until the list's add button shows.
    private func returnToList() -> Bool {
        for _ in 0..<6 {
            if app.buttons["clients.fab.addClient"].isHittable { return true }
            if app.textFields["newClient.firstName"].exists {
                _ = tapIfHittable(app.buttons["Cancel"], timeout: 2)
                continue
            }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists && back.isHittable {
                back.tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            }
        }
        return app.buttons["clients.fab.addClient"].waitForExistence(timeout: 5)
    }
}

/// SplitMix64, local to the UI-test target (the app's copy is DEBUG-only and
/// not linked here).
private struct FuzzRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next(below bound: Int) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Int(z % UInt64(max(1, bound)))
    }
}
