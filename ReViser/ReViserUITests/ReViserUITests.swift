import XCTest

final class ReViserUITests: XCTestCase {
    func testHomeViewButtonsExist() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["Import Document"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Compare Drafts"].waitForExistence(timeout: 2))
    }

    func testCompareDraftsWindowOpens() {
        let app = XCUIApplication()
        app.launch()

        let compareButton = app.buttons["Compare Drafts"]
        XCTAssertTrue(compareButton.waitForExistence(timeout: 2))
        compareButton.tap()

        XCTAssertTrue(app.staticTexts["Compare Drafts"].waitForExistence(timeout: 2))
    }
}

// Project view toolbar / selection edit menu tests

final class ProjectViewToolbarUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSeedProject"]
        app.launch()
        navigateIntoSeededProject()
    }

    private func navigateIntoSeededProject() {
        // SwiftUI on visionOS aggregates the NavigationLink's title + preview text
        // into a single button label like "UITestProject, This is the seeded ...",
        // so we match by label prefix rather than looking for a child staticText.
        let projectButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "UITestProject")
        ).firstMatch
        XCTAssertTrue(projectButton.waitForExistence(timeout: 5),
                      "Seeded project card not found on HomeView")
        projectButton.tap()

        XCTAssertTrue(toolbarButton("arrow.uturn.backward").waitForExistence(timeout: 5),
                      "Did not land in ProjectDetailView (Undo button never appeared)")
    }

    private func toolbarButton(_ query: String) -> XCUIElement {
        return app.buttons[query]
    }

    /// Order mirrors ProjectDetailView.toolbarView
    private static let toolbarIcons: [(String, String)] = [
        ("arrow.uturn.backward", "Undo"),
        ("arrow.uturn.forward", "Redo"),
        ("row-spacing", "Split"),
        ("rectangle.2.swap", "Reorder"),
        ("rectangle.grid.2x2", "Open all sections"),
        ("doc.text", "Restitched manuscript"),
        ("crumpled-paper", "Graveyard"),
        ("note.text.badge.plus", "Notes mode"),
        ("Text Formatting", "Text styling menu"),
        ("Tag", "Tag/filter menu"),
        ("wand.and.sparkles", "Extra tools menu")
    ]

    // All toolbar buttons exist

    func testAllToolbarButtonsExist() {
        for (query, description) in Self.toolbarIcons {
            XCTAssertTrue(toolbarButton(query).exists, "\(description) button (\(query)) missing")
        }

        // Toggle (chevron) — must match by identifier because its label is "Back",
        // which collides with the navigation Back button.
        XCTAssertTrue(toolbarButton("chevron.left").exists,
                      "Toolbar toggle (chevron.left) missing")
    }

    func testUndoRedoInitiallyDisabled() {
        let undo = toolbarButton("arrow.uturn.backward")
        let redo = toolbarButton("arrow.uturn.forward")
        XCTAssertTrue(undo.exists)
        XCTAssertTrue(redo.exists)
        XCTAssertFalse(undo.isEnabled, "Undo should start disabled (no project changes yet)")
        XCTAssertFalse(redo.isEnabled, "Redo should start disabled (no project changes yet)")
    }

    // Toggle hides / restores toolbar

    func testToggleButtonHidesAndRestoresToolbar() {
        let toggleClosed = toolbarButton("chevron.left")
        XCTAssertTrue(toggleClosed.exists)
        toggleClosed.tap()

        let toggleOpen = toolbarButton("chevron.right")
        XCTAssertTrue(toggleOpen.waitForExistence(timeout: 2),
                      "Expected chevron.right after collapsing the toolbar")
        XCTAssertFalse(toolbarButton("arrow.uturn.backward").exists,
                       "Undo should not be present while toolbar is collapsed")

        toggleOpen.tap()
        XCTAssertTrue(toolbarButton("arrow.uturn.backward").waitForExistence(timeout: 2),
                      "Toolbar should reappear after expanding")
    }

    // Menus open and expose expected items

    func testTextStylingMenuOpensWithExpectedItems() {
        toolbarButton("Text Formatting").tap()

        for title in ["Bold", "Italic", "Underline", "Strikethrough",
                      "Text Color", "Highlight", "Font Type", "Font Size"] {
            XCTAssertTrue(menuItemAppears(title), "\"\(title)\" missing from text styling menu")
        }
    }

    func testTagAndFilterMenuOpensWithExpectedItems() {
        toolbarButton("Tag").tap()

        // With no custom tags yet, the menu should still expose the add-category entry
        // and the linked-timeline toggle
        XCTAssertTrue(menuItemAppears("Add New Tag Category"),
                      "Add New Tag Category missing from tag/filter menu")
        XCTAssertTrue(menuItemAppears("Show as linked timeline"),
                      "Show as linked timeline missing from tag/filter menu")
    }

    func testExtraToolsMenuOpensWithExpectedItems() {
        toolbarButton("wand.and.sparkles").tap()

        XCTAssertTrue(menuItemAppears("Section Document by Paragraphs"),
                      "Section Document by Paragraphs missing")
        XCTAssertTrue(menuItemAppears("Rejoin With Next Section"),
                      "Rejoin With Next Section missing")
    }

    // Selection edit menu (UITextView custom UIMenu)

    func testSelectionEditMenuShowsCustomReViserItems() {
        // The seeded section is rendered in a UITextView via TextKitView
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5),
                      "Could not find the section's UITextView")

        // Long-press to surface the edit menu. If that doesn't reveal the menu on this
        // platform variant, fall back to a double-tap selection
        textView.press(forDuration: 1.2)
        if !menuItemAppears("ReViser Tools", timeout: 2)
            && !menuItemAppears("Text Styling", timeout: 0.2)
            && !menuItemAppears("Tag & Filter", timeout: 0.2) {
            app.tap()
            textView.doubleTap()
        }

        // Custom UIMenu nodes returned from selectionEditMenu(suggestedActions)
        let reviserToolsVisible = menuItemAppears("ReViser Tools", timeout: 3)
        let textStylingVisible = menuItemAppears("Text Styling", timeout: 1)
        let tagFilterVisible = menuItemAppears("Tag & Filter", timeout: 1)

        XCTAssertTrue(
            reviserToolsVisible || textStylingVisible || tagFilterVisible,
            "Expected at least one custom selection-edit-menu submenu (ReViser Tools / Text Styling / Tag & Filter) to be visible"
        )

        if reviserToolsVisible {
            tapMenuItem("ReViser Tools")
            // Only the first few items are guaranteed to be visible without scrolling
            // — visionOS renders long UIMenus as a scrollable list and items past the
            // visible window aren't in the accessibility tree.
            for entry in ["Undo", "Redo", "Split Text", "Reorder"] {
                XCTAssertTrue(menuItemAppears(entry, timeout: 2),
                              "\"\(entry)\" missing from ReViser Tools submenu")
            }
        }
    }

    /// SwiftUI Menu items render as buttons, UIKit UIMenu items render as menuItems —
    /// poll both types together so we don't spend our whole budget waiting for the
    /// wrong element type while visionOS auto-dismisses the menu underneath us.
    private func menuItemAppears(_ title: String, timeout: TimeInterval = 2) -> Bool {
        let predicate = NSPredicate(format: "label == %@ OR identifier == %@", title, title)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.menuItems.matching(predicate).firstMatch.exists { return true }
            if app.buttons.matching(predicate).firstMatch.exists { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return false
    }

    private func tapMenuItem(_ title: String) {
        let predicate = NSPredicate(format: "label == %@ OR identifier == %@", title, title)
        let menuItem = app.menuItems.matching(predicate).firstMatch
        if menuItem.exists {
            menuItem.tap()
            return
        }
        let button = app.buttons.matching(predicate).firstMatch
        if button.exists {
            button.tap()
        }
    }
}
