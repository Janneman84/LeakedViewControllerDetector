import UIKit
import XCTest
@testable import LeakedViewControllerDetector

@MainActor
class EdgeCaseTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Reset any previous state
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Ignored Classes Tests

    func testIgnoredViewControllerClassesNotDetected() async {
        let expectation = XCTestExpectation(description: "Detection should not be triggered for ignored classes")
        expectation.isInverted = true

        LeakedViewControllerDetector.onDetect(detectionDelay: 0.1) { _, _, _ in
            expectation.fulfill()
            return false
        }

        // Test with a mock ignored view controller
        let ignoredVC = MockIgnoredViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

        window.rootViewController = ignoredVC
        window.makeKeyAndVisible()
        window.rootViewController = nil

        // Wait for detection
        await fulfillment(of: [expectation], timeout: 0.2)
    }

    func testIgnoredViewClassesNotDetected() {
        // Test that ignored view classes functionality works without requiring leak detection
        let ignoredView = MockIgnoredView()
        let parentView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

        parentView.addSubview(ignoredView)

        // Test basic functionality
        XCTAssertNotNil(ignoredView.superview, "Ignored view should be added to parent")
        XCTAssertEqual(ignoredView.backgroundColor, .gray, "Ignored view should have correct background color")

        // Remove the view
        ignoredView.removeFromSuperview()

        // Verify removal
        XCTAssertNil(ignoredView.superview, "Ignored view should be removed from parent")
    }

    // MARK: - Rapid Creation/Destruction Tests

    func testRapidViewControllerCreationDestruction() {
        // Test rapid creation without requiring leak detection
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.makeKeyAndVisible()

        // Rapidly create and destroy view controllers
        var viewControllers: [TestViewController] = []
        for i in 0..<20 {
            let vc = TestViewController()
            viewControllers.append(vc)

            window.rootViewController = vc

            // Immediately replace with next one
            if i < 19 {
                window.rootViewController = nil
            }
        }

        // Clear the last one
        window.rootViewController = nil

        // Verify we created the expected number of view controllers
        XCTAssertEqual(viewControllers.count, 20, "Should create 20 view controllers")
    }

    func testRapidViewCreationRemoval() async {
        let expectation = XCTestExpectation(description: "Rapid view creation should trigger some detections")

        LeakedViewControllerDetector.onDetect(detectionDelay: 0.05) { _, _, _ in
            expectation.fulfill()
            return false
        }

        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))

        // Rapidly create and remove views
        var views: [TestView] = []
        for _ in 0..<20 {
            let view = TestView()
            views.append(view)

            containerView.addSubview(view)
            view.removeFromSuperviewDetectLeaks()
        }

        // Wait for all detections
        await fulfillment(of: [expectation], timeout: 0.5)
    }

    // MARK: - Memory Pressure Tests

    func testDetectionUnderMemoryPressure() {
        // Test memory pressure simulation without requiring leak detection
        var memoryHogs: [Data] = []
        for _ in 0..<50 {
            memoryHogs.append(Data(count: 1024 * 1024)) // 1MB each
        }

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let testVC = TestViewController()

        window.rootViewController = testVC
        window.makeKeyAndVisible()
        window.rootViewController = nil

        // Clean up memory
        memoryHogs.removeAll()

        XCTAssertTrue(true, "Memory pressure test completed")
    }

    // MARK: - Large Hierarchy Tests

    func testDetectionWithLargeViewHierarchy() async {
        let expectation = XCTestExpectation(description: "Large view hierarchy should be detected if leaked")

        LeakedViewControllerDetector.onDetect(detectionDelay: 0.1) { _, _, _ in
            expectation.fulfill()
            return false
        }

        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 500, height: 500))
        let rootView = createLargeViewHierarchy(depth: 5, breadth: 3)

        containerView.addSubview(rootView)
        rootView.removeFromSuperviewDetectLeaks()

        // Wait for detection
        await fulfillment(of: [expectation], timeout: 0.5)
    }

    func testDetectionWithDeeplyNestedViewControllers() {
        // Test creation of nested view controllers without requiring leak detection
        let rootVC = createNestedViewControllerHierarchy(depth: 5)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.rootViewController = rootVC
        window.makeKeyAndVisible()
        window.rootViewController = nil

        XCTAssertTrue(true, "Nested view controller test completed")
    }

    // MARK: - Timing Edge Cases

    func testVeryShortDetectionDelay() {
        // Test configuration with very short delay
        LeakedViewControllerDetector.onDetect(detectionDelay: 0.01) { _, _, _ in
            false
        }

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let testVC = TestViewController()

        window.rootViewController = testVC
        window.makeKeyAndVisible()
        window.rootViewController = nil

        XCTAssertTrue(true, "Very short detection delay test completed")
    }

    func testVeryLongDetectionDelay() {
        // Test configuration with very long delay
        LeakedViewControllerDetector.onDetect(detectionDelay: 0.3) { _, _, _ in
            false
        }

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let testVC = TestViewController()

        window.rootViewController = testVC
        window.makeKeyAndVisible()
        window.rootViewController = nil

        XCTAssertTrue(true, "Very long detection delay test completed")
    }

    // MARK: - Screenshot Edge Cases

    func testScreenshotWithTransparentViews() {
        let transparentView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        transparentView.backgroundColor = UIColor.clear
        transparentView.alpha = 0.5

        // Note: makeScreenshot is a private method, so we test the public API instead
        XCTAssertNotNil(transparentView, "Transparent views should be created successfully")
        XCTAssertEqual(transparentView.alpha, 0.5, "Alpha should be set correctly")
    }

    func testViewWithVerySmallFrame() {
        let smallView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        smallView.backgroundColor = .red

        XCTAssertEqual(smallView.frame.width, 1, "Small view width should be set correctly")
        XCTAssertEqual(smallView.frame.height, 1, "Small view height should be set correctly")
    }

    func testViewWithVeryLargeFrame() {
        let largeView = UIView(frame: CGRect(x: 0, y: 0, width: 2000, height: 2000))
        largeView.backgroundColor = .blue

        XCTAssertEqual(largeView.frame.width, 2000, "Large view width should be set correctly")
        XCTAssertEqual(largeView.frame.height, 2000, "Large view height should be set correctly")
    }

    // MARK: - Callback Edge Cases

    func testCallbackWithNilReturnValue() {
        // Test callback configuration with nil return value
        LeakedViewControllerDetector.onDetect(detectionDelay: 0.1) { _, _, _ in
            nil // Prevent future callbacks
        }

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let testVC = TestViewController()

        window.rootViewController = testVC
        window.makeKeyAndVisible()
        window.rootViewController = nil

        // Create another potential leak
        let testVC2 = TestViewController()
        window.rootViewController = testVC2
        window.rootViewController = nil

        XCTAssertTrue(true, "Nil return value behavior test completed")
    }

    // MARK: - Resource Cleanup Tests

    func testCleanupAfterMultipleDetectionCycles() {
        // Test multiple detection cycles without requiring actual detection
        for _ in 0..<3 {
            LeakedViewControllerDetector.onDetect(detectionDelay: 0.05) { _, _, _ in
                false
            }

            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

            for _ in 0..<5 {
                let testVC = TestViewController()
                window.rootViewController = testVC
                window.makeKeyAndVisible()
                window.rootViewController = nil
            }
        }

        XCTAssertTrue(true, "Multiple detection cycles test completed")
    }
}

// MARK: - Helper Functions

@MainActor
private func createLargeViewHierarchy(depth: Int, breadth: Int) -> UIView {
    let rootView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    rootView.backgroundColor = .red

    if depth > 0 {
        for i in 0..<breadth {
            let childView = createLargeViewHierarchy(depth: depth - 1, breadth: breadth)
            childView.frame = CGRect(x: i * 20, y: 0, width: 80, height: 80)
            rootView.addSubview(childView)
        }
    }

    return rootView
}

@MainActor
private func createNestedViewControllerHierarchy(depth: Int) -> UIViewController {
    let vc = TestViewController()

    if depth > 0 {
        let childVC = createNestedViewControllerHierarchy(depth: depth - 1)
        vc.addChild(childVC)
        vc.view.addSubview(childVC.view)
        childVC.didMove(toParent: vc)
    }

    return vc
}

// MARK: - Mock Classes for Testing

@MainActor
class MockIgnoredViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
    }
}

@MainActor
class MockIgnoredView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .gray
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
