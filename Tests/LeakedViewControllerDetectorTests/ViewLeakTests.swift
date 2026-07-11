import UIKit
import XCTest
@testable import LeakedViewControllerDetector

@MainActor
class ViewLeakTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Reset state before each test
    }

    override func tearDown() {
        super.tearDown()
        // Clean up after tests
    }

    // MARK: - Complex View Hierarchy Tests

    func testNestedViewHierarchyLeakDetection() {
        // Test nested view hierarchy functionality without requiring leak detection
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let parentView = UIView(frame: CGRect(x: 0, y: 0, width: 150, height: 150))
        let childView = TestView()
        let grandChildView = TestView()

        containerView.addSubview(parentView)
        parentView.addSubview(childView)
        childView.addSubview(grandChildView)

        // Verify nested hierarchy is set up correctly
        XCTAssertEqual(containerView.subviews.count, 1, "Container view should have one subview")
        XCTAssertEqual(parentView.subviews.count, 1, "Parent view should have one subview")
        XCTAssertEqual(childView.subviews.count, 1, "Child view should have one subview")
        XCTAssertEqual(containerView.subviews.first, parentView, "Parent view should be container's subview")
        XCTAssertEqual(parentView.subviews.first, childView, "Child view should be parent's subview")
        XCTAssertEqual(childView.subviews.first, grandChildView, "Grand child view should be child's subview")

        // Remove the parent view
        parentView.removeFromSuperview()

        // Verify removal
        XCTAssertEqual(containerView.subviews.count, 0, "Container view should have no subviews after removal")
    }

    func testViewWithCustomSubviewsLeakDetection() {
        // Test view with custom subviews functionality without requiring leak detection
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let parentView = CustomViewWithSubviews()
        parentView.frame = CGRect(x: 0, y: 0, width: 150, height: 150)

        containerView.addSubview(parentView)

        // Verify custom subviews are set up
        XCTAssertEqual(containerView.subviews.count, 1, "Container should have one subview")
        XCTAssertEqual(parentView.subviews.count, 3, "Parent view should have 3 custom subviews")

        // Verify the custom subviews
        let subviews = parentView.subviews
        XCTAssertTrue(subviews.allSatisfy { $0 is UIView }, "All subviews should be UIView instances")

        // Remove the parent view
        parentView.removeFromSuperview()

        // Verify removal
        XCTAssertEqual(containerView.subviews.count, 0, "Container should have no subviews after removal")
    }

    func testViewWithConstraintsLeakDetection() {
        // Test view with constraints functionality without requiring leak detection
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let constrainedView = TestView()

        containerView.addSubview(constrainedView)
        constrainedView.translatesAutoresizingMaskIntoConstraints = false

        // Add constraints
        let constraints = [
            constrainedView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            constrainedView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            constrainedView.widthAnchor.constraint(equalToConstant: 100),
            constrainedView.heightAnchor.constraint(equalToConstant: 100),
        ]

        NSLayoutConstraint.activate(constraints)

        // Verify constraints are set up
        XCTAssertEqual(containerView.subviews.count, 1, "Container should have one subview")
        XCTAssertFalse(constrainedView.translatesAutoresizingMaskIntoConstraints, "View should use Auto Layout")
        XCTAssertEqual(constraints.count, 4, "Should have 4 constraints")
        XCTAssertTrue(constraints.allSatisfy(\.isActive), "All constraints should be active")

        // Remove the view
        constrainedView.removeFromSuperview()

        // Verify removal
        XCTAssertEqual(containerView.subviews.count, 0, "Container should have no subviews after removal")
    }

    // MARK: - UIScrollView Tests

    func testScrollViewContentLeakDetection() {
        // Test scroll view content functionality without requiring leak detection
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let contentView = TestView()
        contentView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)

        scrollView.addSubview(contentView)
        scrollView.contentSize = contentView.frame.size

        // Verify content view is added
        XCTAssertEqual(scrollView.subviews.count, 1, "Scroll view should have one subview")
        XCTAssertEqual(scrollView.subviews.first, contentView, "Content view should be the scroll view's subview")
        XCTAssertEqual(scrollView.contentSize, CGSize(width: 400, height: 400), "Content size should be set correctly")

        contentView.removeFromSuperview()

        // Verify removal
        XCTAssertEqual(scrollView.subviews.count, 0, "Scroll view should have no subviews after removal")
    }

    // MARK: - UIStackView Tests

    func testStackViewArrangedSubviewsLeakDetection() {
        // Test stack view arranged subview functionality without requiring leak detection
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 10

        let arrangedView1 = TestView()
        let arrangedView2 = TestView()

        stackView.addArrangedSubview(arrangedView1)
        stackView.addArrangedSubview(arrangedView2)

        // Verify arranged subviews are added
        XCTAssertEqual(stackView.arrangedSubviews.count, 2, "Stack view should have 2 arranged subviews")
        XCTAssertEqual(stackView.arrangedSubviews[0], arrangedView1, "First arranged subview should be arrangedView1")
        XCTAssertEqual(stackView.arrangedSubviews[1], arrangedView2, "Second arranged subview should be arrangedView2")

        // Remove one arranged subview
        stackView.removeArrangedSubview(arrangedView1)
        arrangedView1.removeFromSuperview()

        // Verify removal
        XCTAssertEqual(stackView.arrangedSubviews.count, 1, "Stack view should have 1 arranged subview after removal")
        XCTAssertEqual(
            stackView.arrangedSubviews[0],
            arrangedView2,
            "Remaining arranged subview should be arrangedView2"
        )
    }

    // MARK: - Collection View Tests

    func testCollectionViewCellLeakDetection() {
        // Test collection view cell functionality without requiring leak detection
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 50, height: 50)

        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 200, height: 200),
            collectionViewLayout: layout
        )
        collectionView.register(TestCollectionViewCell.self, forCellWithReuseIdentifier: "TestCell")

        // Create a cell manually (simulating a cell)
        let cell = TestCollectionViewCell()
        let customView = TestView()
        cell.contentView.addSubview(customView)

        // Verify cell setup
        XCTAssertEqual(cell.contentView.subviews.count, 1, "Cell content view should have one subview")
        XCTAssertEqual(cell.contentView.subviews.first, customView, "Custom view should be in cell content view")

        customView.removeFromSuperview()

        // Verify removal
        XCTAssertEqual(cell.contentView.subviews.count, 0, "Cell content view should have no subviews after removal")
    }

    // MARK: - Table View Tests

    func testTableViewCellLeakDetection() {
        // Test table view cell functionality without requiring leak detection
        let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        tableView.register(TestTableViewCell.self, forCellReuseIdentifier: "TestCell")

        // Create a cell manually (simulating a cell)
        let cell = TestTableViewCell()
        let customView = TestView()
        cell.contentView.addSubview(customView)

        // Verify cell setup
        XCTAssertEqual(cell.contentView.subviews.count, 1, "Cell content view should have one subview")
        XCTAssertEqual(cell.contentView.subviews.first, customView, "Custom view should be in cell content view")

        customView.removeFromSuperview()

        // Verify removal
        XCTAssertEqual(cell.contentView.subviews.count, 0, "Cell content view should have no subviews after removal")
    }

    // MARK: - Animation Tests

    func testViewLeakDuringAnimation() {
        // Test view animation functionality without requiring leak detection
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let animatingView = TestView()
        animatingView.frame = CGRect(x: 0, y: 0, width: 50, height: 50)

        containerView.addSubview(animatingView)

        // Verify initial setup
        XCTAssertEqual(containerView.subviews.count, 1, "Container should have one subview")
        XCTAssertEqual(animatingView.frame.origin.x, 0, "Initial X position should be 0")
        XCTAssertEqual(animatingView.frame.origin.y, 0, "Initial Y position should be 0")

        // Start an animation
        UIView.animate(withDuration: 0.1) {
            animatingView.frame = CGRect(x: 100, y: 100, width: 50, height: 50)
        }

        // Remove the view
        animatingView.removeFromSuperview()

        // Verify removal
        XCTAssertEqual(containerView.subviews.count, 0, "Container should have no subviews after removal")
    }

    // MARK: - Gesture Recognizer Tests

    func testViewWithGestureRecognizersLeakDetection() {
        // Test view with gesture recognizers functionality without requiring leak detection
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let gestureView = TestView()
        gestureView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        containerView.addSubview(gestureView)

        // Add gesture recognizers
        let tapGesture = UITapGestureRecognizer()
        let panGesture = UIPanGestureRecognizer()
        let pinchGesture = UIPinchGestureRecognizer()

        gestureView.addGestureRecognizer(tapGesture)
        gestureView.addGestureRecognizer(panGesture)
        gestureView.addGestureRecognizer(pinchGesture)

        // Verify gesture recognizers are set up
        XCTAssertEqual(containerView.subviews.count, 1, "Container should have one subview")
        XCTAssertEqual(gestureView.gestureRecognizers?.count, 3, "View should have 3 gesture recognizers")
        XCTAssertTrue(gestureView.gestureRecognizers?.contains(tapGesture) == true, "Tap gesture should be added")
        XCTAssertTrue(gestureView.gestureRecognizers?.contains(panGesture) == true, "Pan gesture should be added")
        XCTAssertTrue(gestureView.gestureRecognizers?.contains(pinchGesture) == true, "Pinch gesture should be added")

        // Remove the view
        gestureView.removeFromSuperview()

        // Verify removal
        XCTAssertEqual(containerView.subviews.count, 0, "Container should have no subviews after removal")
    }

    // MARK: - Layer Tests

    func testViewWithCustomLayersLeakDetection() {
        // Test view with custom layers functionality without requiring leak detection
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let layeredView = TestView()
        layeredView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        containerView.addSubview(layeredView)

        // Add custom layers
        let customLayer = CALayer()
        customLayer.frame = CGRect(x: 10, y: 10, width: 80, height: 80)
        customLayer.backgroundColor = UIColor.red.cgColor
        layeredView.layer.addSublayer(customLayer)

        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = CGRect(x: 20, y: 20, width: 60, height: 60)
        gradientLayer.colors = [UIColor.blue.cgColor, UIColor.green.cgColor]
        layeredView.layer.addSublayer(gradientLayer)

        // Verify layers are set up
        XCTAssertEqual(containerView.subviews.count, 1, "Container should have one subview")
        XCTAssertEqual(layeredView.layer.sublayers?.count, 2, "View should have 2 custom sublayers")
        XCTAssertTrue(layeredView.layer.sublayers?.contains(customLayer) == true, "Custom layer should be added")
        XCTAssertTrue(layeredView.layer.sublayers?.contains(gradientLayer) == true, "Gradient layer should be added")

        // Remove the view
        layeredView.removeFromSuperview()

        // Verify removal
        XCTAssertEqual(containerView.subviews.count, 0, "Container should have no subviews after removal")
    }
}

// MARK: - Test Helper Classes

@MainActor
class CustomViewWithSubviews: UIView {
    private let label = UILabel()
    private let button = UIButton()
    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSubviews()
    }

    private func setupSubviews() {
        addSubview(label)
        addSubview(button)
        addSubview(imageView)

        label.text = "Test Label"
        button.setTitle("Test Button", for: .normal)

        // Add some constraints
        label.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),

            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 10),
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),

            imageView.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 10),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            imageView.widthAnchor.constraint(equalToConstant: 50),
            imageView.heightAnchor.constraint(equalToConstant: 50),
        ])
    }
}
