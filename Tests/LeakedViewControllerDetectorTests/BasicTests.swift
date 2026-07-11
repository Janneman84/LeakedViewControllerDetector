import UIKit
import XCTest
@testable import LeakedViewControllerDetector

@MainActor
class BasicTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Reset any previous state
    }

    override func tearDown() {
        super.tearDown()
    }

    func testBasicConfiguration() {
        // Test that we can configure the detector without crashing
        let expectation = XCTestExpectation(description: "Callback should not be invoked immediately")
        expectation.isInverted = true // We expect this NOT to be fulfilled

        LeakedViewControllerDetector.onDetect(detectionDelay: 0.1) { _, _, _ in
            expectation.fulfill()
            return false
        }

        // Wait a short time to ensure callback isn't called immediately
        wait(for: [expectation], timeout: 0.05)
    }

    func testIgnoredClassNames() {
        // Test that ignored class names are properly configured
        let ignoredVCs = LeakedViewControllerDetector.ignoredViewControllerClassNames
        let ignoredViews = LeakedViewControllerDetector.ignoredViewClassNames
        let ignoredWindows = LeakedViewControllerDetector.ignoredWindowClassNames

        XCTAssertTrue(!ignoredVCs.isEmpty, "Should have ignored view controller classes")
        XCTAssertTrue(!ignoredViews.isEmpty, "Should have ignored view classes")
        XCTAssertTrue(!ignoredWindows.isEmpty, "Should have ignored window classes")

        XCTAssertTrue(ignoredVCs.contains("UICompatibilityInputViewController"))
        XCTAssertTrue(ignoredWindows.contains("UIRemoteKeyboardWindow"))
    }

    func testViewControllerCreation() {
        // Test basic view controller creation and setup
        let testVC = UIViewController()
        testVC.loadViewIfNeeded()

        XCTAssertNotNil(testVC.view, "View controller should have a view")
        XCTAssertTrue(testVC.isViewLoaded, "View should be loaded")
    }

    func testViewRemovalMethod() {
        // Test that the removeFromSuperviewDetectLeaks method exists and can be called
        let parentView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let childView = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))

        parentView.addSubview(childView)
        XCTAssertEqual(parentView.subviews.count, 1, "Parent should have one subview")

        // This should not crash
        childView.removeFromSuperviewDetectLeaks()
        XCTAssertEqual(parentView.subviews.count, 0, "Parent should have no subviews after removal")
    }

    func testDetectorConfiguration() {
        // Test that we can configure the detector with different delays
        LeakedViewControllerDetector.onDetect(detectionDelay: 0.5) { _, _, _ in
            false
        }

        LeakedViewControllerDetector.onDetect(detectionDelay: 1.0) { _, _, _ in
            true
        }

        // Configuration should not crash
        XCTAssertTrue(true, "Detector configuration should work without crashing")
    }

    func testCallbackMechanism() async {
        // Test that the callback mechanism works by using the view removal detection
        let expectation = XCTestExpectation(description: "View removal should trigger callback")

        LeakedViewControllerDetector.onDetect(detectionDelay: 0.1) { _, _, _ in
            expectation.fulfill()
            return false
        }

        // Create a view hierarchy that will trigger the detection
        let parentView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let childView = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        let subChildView = UIView(frame: CGRect(x: 0, y: 0, width: 25, height: 25))

        // Build hierarchy
        parentView.addSubview(childView)
        childView.addSubview(subChildView)

        // Use the removeFromSuperviewDetectLeaks method which should trigger detection
        childView.removeFromSuperviewDetectLeaks()

        // Wait for detection callback
        await fulfillment(of: [expectation], timeout: 0.5)
    }
}
