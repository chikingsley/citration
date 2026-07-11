import XCTest

final class IPadAdaptiveUITests: XCTestCase {
    @MainActor
    func testLibraryAdaptsAcrossPortraitAndLandscape() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        let portraitLibrary = app.navigationBars["Library"].waitForExistence(timeout: 10)
        XCTAssertTrue(portraitLibrary)

        XCUIDevice.shared.orientation = .landscapeLeft

        let landscapeLibrary = app.navigationBars["Library"].waitForExistence(timeout: 5)
        let landscapeSearch = app.searchFields["Search library"].exists
        XCTAssertTrue(landscapeLibrary)
        XCTAssertTrue(landscapeSearch)

        XCUIDevice.shared.orientation = .portrait
    }
}
