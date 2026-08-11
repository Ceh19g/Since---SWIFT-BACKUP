import XCTest

final class SinceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateFirstHabit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Start your first timeline"].waitForExistence(timeout: 5))
        app.buttons["empty-create-habit-button"].tap()

        let nameField = app.textFields["habit-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("No alcohol")

        let createButton = app.buttons["create-habit-button"]
        XCTAssertTrue(createButton.isEnabled)
        createButton.tap()

        XCTAssertTrue(app.staticTexts["No alcohol"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Record a slip"].exists)

        let detailLink = app.buttons["View details for No alcohol"]
        XCTAssertTrue(detailLink.waitForExistence(timeout: 3))
        detailLink.tap()
        XCTAssertTrue(app.navigationBars["No alcohol"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCreateDailyHabitAndCompleteToday() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Start your first timeline"].waitForExistence(timeout: 5))
        app.buttons["empty-create-habit-button"].tap()

        let nameField = app.textFields["habit-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Read")

        let dailyStyle = app.buttons["tracking-style-positiveStreak"]
        XCTAssertTrue(dailyStyle.waitForExistence(timeout: 3))
        dailyStyle.tap()
        app.buttons["create-habit-button"].tap()

        let completeButton = app.buttons["Mark today complete"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.tap()

        let completedButton = app.buttons["Completed today"]
        XCTAssertTrue(completedButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["day streak"].exists)

        completedButton.tap()
        XCTAssertTrue(app.buttons["Mark today complete"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMeasuredHabitAsksForAmountBeforeCompletion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Start your first timeline"].waitForExistence(timeout: 5))
        app.buttons["empty-create-habit-button"].tap()

        let nameField = app.textFields["habit-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Read")
        app.buttons["tracking-style-positiveStreak"].tap()

        app.swipeUp()
        app.swipeUp()

        let moreOptions = app.buttons["habit-more-options-button"]
        XCTAssertTrue(moreOptions.waitForExistence(timeout: 3))
        moreOptions.tap()
        app.swipeUp()

        let measurementPicker = app.buttons["habit-measurement-picker"]
        XCTAssertTrue(measurementPicker.waitForExistence(timeout: 3))
        measurementPicker.tap()
        XCTAssertTrue(app.buttons["Pages"].waitForExistence(timeout: 3))
        app.buttons["Pages"].tap()
        app.buttons["create-habit-button"].tap()

        let completeButton = app.buttons["Mark today complete"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.tap()

        XCTAssertTrue(app.staticTexts["How many pages?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["measurement-value-field"].exists)
        XCTAssertTrue(app.buttons["save-habit-measurement-button"].isEnabled)
        app.buttons["save-habit-measurement-button"].tap()
        XCTAssertTrue(app.buttons["Completed today"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEditAndDeleteHabit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Start your first timeline"].waitForExistence(timeout: 5))
        app.buttons["empty-create-habit-button"].tap()

        let nameField = app.textFields["habit-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("No alcohol")
        app.buttons["create-habit-button"].tap()

        app.tabBars.buttons["Habits"].tap()
        XCTAssertTrue(app.staticTexts["No alcohol"].waitForExistence(timeout: 5))
        app.staticTexts["No alcohol"].tap()

        let optionsButton = app.buttons["Habit options"]
        XCTAssertTrue(optionsButton.waitForExistence(timeout: 3))
        optionsButton.tap()
        app.buttons["edit-habit-menu-button"].tap()

        let editNameField = app.textFields["edit-habit-name-field"]
        XCTAssertTrue(editNameField.waitForExistence(timeout: 3))
        editNameField.tap()
        editNameField.typeText(" updated")
        app.buttons["save-habit-button"].tap()

        XCTAssertTrue(app.navigationBars["No alcohol updated"].waitForExistence(timeout: 5))

        optionsButton.tap()
        app.buttons["delete-habit-menu-button"].tap()
        let confirmDelete = app.alerts.buttons["confirm-delete-habit-button"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 3))
        confirmDelete.tap()

        XCTAssertTrue(app.staticTexts["No habits yet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCreateCompleteAndEditPlannerTask() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()

        let addTaskButton = app.buttons["add-planner-task-button"]
        XCTAssertTrue(addTaskButton.waitForExistence(timeout: 5))
        addTaskButton.tap()

        let titleField = app.textFields["planner-task-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.tap()
        titleField.typeText("Take a walk")
        app.buttons["save-planner-task-button"].tap()

        XCTAssertTrue(app.buttons["Take a walk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 of 1 completed"].exists)

        let completeButton = app.buttons["Complete Take a walk"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 3))
        completeButton.tap()
        XCTAssertTrue(app.staticTexts["1 of 1 completed"].waitForExistence(timeout: 3))

        let completedDisclosure = app.buttons["Completed 1"]
        XCTAssertTrue(completedDisclosure.waitForExistence(timeout: 3))
        completedDisclosure.tap()
        app.buttons["Take a walk"].tap()
        XCTAssertTrue(app.navigationBars["Edit task"].waitForExistence(timeout: 3))
        titleField.tap()
        titleField.typeText(" outside")
        app.buttons["save-planner-task-button"].tap()

        XCTAssertTrue(app.buttons["Take a walk outside"].waitForExistence(timeout: 5))

        let optionsButton = app.buttons["Options for Take a walk outside"]
        XCTAssertTrue(optionsButton.waitForExistence(timeout: 3))
        optionsButton.tap()
        app.buttons["Delete"].tap()
        app.buttons["confirm-delete-planner-task-button"].tap()

        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 8))
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons["Take a walk outside"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testMoreScreenOpensInsightsAndHasBackupActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()

        app.tabBars.buttons["More"].tap()

        XCTAssertTrue(app.staticTexts["Insights"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["export-backup-button"].exists)
        XCTAssertTrue(app.buttons["restore-backup-button"].exists)
        XCTAssertFalse(app.staticTexts["Settings"].exists)

        let insightsButton = app.buttons["open-insights-button"]
        XCTAssertTrue(insightsButton.exists)
        insightsButton.tap()

        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No activity yet"].exists)
        XCTAssertTrue(app.buttons["insights-habit-filter"].exists)
        XCTAssertFalse(app.staticTexts["IN PROGRESS"].exists)
    }

    @MainActor
    func testAppearanceAndOptionalControlsAreAvailable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()

        app.tabBars.buttons["More"].tap()
        let appearancePicker = app.segmentedControls["appearance-picker"]
        XCTAssertTrue(appearancePicker.waitForExistence(timeout: 5))
        XCTAssertTrue(appearancePicker.buttons["System"].exists)
        XCTAssertTrue(appearancePicker.buttons["Light"].exists)
        XCTAssertTrue(appearancePicker.buttons["Dark"].exists)

        appearancePicker.buttons["Dark"].tap()
        XCTAssertTrue(appearancePicker.buttons["Dark"].isSelected)
        appearancePicker.buttons["Light"].tap()
        XCTAssertTrue(appearancePicker.buttons["Light"].isSelected)
        appearancePicker.buttons["System"].tap()
        XCTAssertTrue(appearancePicker.buttons["System"].isSelected)

        app.tabBars.buttons["Today"].tap()
        app.buttons["empty-create-habit-button"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["habit-more-options-button"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["habit-measurement-picker"].exists)
        app.buttons["habit-more-options-button"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["habit-measurement-picker"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCalendarShowsTasksAndOpensDayDetails() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()

        let addTaskButton = app.buttons["add-planner-task-button"]
        XCTAssertTrue(addTaskButton.waitForExistence(timeout: 5))
        addTaskButton.tap()

        let titleField = app.textFields["planner-task-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.tap()
        titleField.typeText("Calendar task")
        app.buttons["save-planner-task-button"].tap()
        XCTAssertTrue(app.buttons["Calendar task"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.buttons["calendar-filter-menu"].waitForExistence(timeout: 5))

        let todayCell = app.buttons["calendar-today-cell"]
        XCTAssertTrue(todayCell.waitForExistence(timeout: 5))
        todayCell.tap()

        XCTAssertTrue(app.staticTexts["Calendar task"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0/1"].exists)

        let completeButton = app.buttons["Complete Calendar task"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 3))
        completeButton.tap()
        XCTAssertTrue(app.staticTexts["1/1"].waitForExistence(timeout: 3))

        app.buttons["calendar-add-task-button"].tap()
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.tap()
        titleField.typeText("Added from calendar")
        app.buttons["save-planner-task-button"].tap()

        XCTAssertTrue(app.staticTexts["Added from calendar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1/2"].exists)
    }

    @MainActor
    func testPlannerInboxQuickCapture() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()

        app.tabBars.buttons["Planner"].tap()
        XCTAssertTrue(app.navigationBars["Planner"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["planner-filter-overdue"].waitForExistence(timeout: 3))

        let quickField = app.textFields["planner-quick-task-field"]
        XCTAssertTrue(quickField.waitForExistence(timeout: 3))
        quickField.tap()
        quickField.typeText("Sort weekend plans")
        app.buttons["planner-quick-add-button"].tap()

        XCTAssertTrue(app.buttons["Sort weekend plans"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.keyboards.count, 0, "Quick capture should dismiss the keyboard after adding a task")
        XCTAssertTrue(app.staticTexts["Inbox"].exists)

        app.tabBars.buttons["Today"].tap()
        XCTAssertFalse(app.buttons["Sort weekend plans"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testUpcomingTaskShowsScheduledDate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()

        app.tabBars.buttons["Planner"].tap()
        XCTAssertTrue(app.navigationBars["Planner"].waitForExistence(timeout: 5))

        let upcomingFilter = app.buttons["planner-filter-upcoming"]
        XCTAssertTrue(upcomingFilter.waitForExistence(timeout: 3))
        upcomingFilter.tap()

        app.buttons["planner-add-task-button"].tap()
        let titleField = app.textFields["planner-task-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.tap()
        titleField.typeText("Upcoming appointment")
        app.buttons["save-planner-task-button"].tap()

        XCTAssertTrue(app.staticTexts["Upcoming appointment"].waitForExistence(timeout: 5))
        let scheduledDate = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'planner-scheduled-date-'"))
            .firstMatch
        XCTAssertTrue(scheduledDate.waitForExistence(timeout: 3))
        XCTAssertFalse(scheduledDate.label.isEmpty)
    }

    @MainActor
    func testCreateAppleHealthStepTracker() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset", "--ui-testing-health-steps"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Start your first timeline"].waitForExistence(timeout: 5))
        app.buttons["empty-create-habit-button"].tap()

        let healthStyle = app.buttons["tracking-style-health-steps"]
        XCTAssertTrue(healthStyle.waitForExistence(timeout: 3))
        healthStyle.tap()

        XCTAssertEqual(app.textFields["habit-name-field"].value as? String, "Daily Steps")
        app.buttons["create-habit-button"].tap()

        let heroCard = app.descendants(matching: .any)["health-steps-hero-card"]
        XCTAssertTrue(heroCard.waitForExistence(timeout: 5))
        let displayedSteps = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS '6,842'"))
            .firstMatch
        XCTAssertTrue(displayedSteps.waitForExistence(timeout: 3))

        app.tabBars.buttons["More"].tap()
        let healthConnection = app.buttons["open-apple-health-button"]
        XCTAssertTrue(healthConnection.waitForExistence(timeout: 5))
        healthConnection.tap()

        XCTAssertTrue(app.navigationBars["Apple Health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Daily totals are displayed only inside Since"].exists)
    }
}
