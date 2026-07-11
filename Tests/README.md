# LeakedViewControllerDetector Test Suite

This directory contains a comprehensive test suite for the LeakedViewControllerDetector library using Swift Testing framework.

## Overview

The test suite includes over 50 test cases covering all aspects of memory leak detection for view controllers and views in iOS applications. Tests are designed to verify functionality, edge cases, performance, and Swift 6 concurrency safety.

## Test Structure

### Test Files

| File | Purpose | Test Count |
|------|---------|------------|
| `LeakedViewControllerDetectorTests.swift` | Core functionality and configuration | ~15 tests |
| `ViewLeakTests.swift` | View-specific leak detection scenarios | ~12 tests |
| `ViewControllerLeakTests.swift` | View controller leak detection scenarios | ~15 tests |
| `EdgeCaseTests.swift` | Edge cases, performance, and stress tests | ~15 tests |

### Test Categories

#### 🔧 Configuration Tests
- Callback setup and invocation
- Detection delay configuration
- Ignored class verification
- Return value handling

#### 📱 View Controller Tests
- Modal presentation/dismissal
- Navigation controller operations
- Tab bar controller switching
- Page view controller transitions
- Split view controller scenarios
- Container view controllers
- Memory warnings
- Notification observers
- Timer management

#### 🎨 View Tests
- Nested view hierarchies
- Auto Layout constraints
- UIScrollView content
- UIStackView arranged subviews
- Collection/Table view cells
- Animation handling
- Gesture recognizers
- Custom layers

#### ⚡ Performance & Edge Cases
- Rapid creation/destruction
- Memory pressure conditions
- Concurrent operations
- Large hierarchies
- Timing edge cases
- Application state transitions
- Screenshot generation
- Resource cleanup

## Running Tests

### Prerequisites
- Xcode 15.0+
- iOS 13.0+ Simulator
- Swift 6.0+

### Command Line

```bash
# Run all tests
swift test --destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test suite
swift test --filter "LeakedViewControllerDetector Tests"
swift test --filter "View Leak Detection Tests"
swift test --filter "View Controller Leak Detection Tests"
swift test --filter "Edge Cases and Performance Tests"

# Run with verbose output
swift test --verbose

# Run specific test
swift test --filter "testViewControllerLifecycle"
```

### Xcode

1. Open the package in Xcode
2. Select an iOS simulator (iPhone 15 recommended)
3. Press `Cmd+U` to run all tests
4. Use the Test Navigator to run specific test suites

## Test Helper Classes

### Core Helpers
- **`TestViewController`**: Basic view controller for testing
- **`TestView`**: Basic view for testing
- **`CustomViewWithSubviews`**: Complex view with multiple subviews and constraints

### Specialized Helpers
- **`MemoryWarningTestViewController`**: Simulates memory pressure scenarios
- **`DelayedViewLoadingViewController`**: Tests async view loading
- **`NotificationObserverViewController`**: Tests notification-related leaks
- **`TimerViewController`**: Tests timer-related leaks
- **`TestCollectionViewCell`** / **`TestTableViewCell`**: Cell testing

### Mock Classes
- **`MockIgnoredViewController`**: Tests ignored class functionality
- **`MockIgnoredView`**: Tests ignored view functionality

## Test Patterns

### Async Testing
```swift
@Test("Test description")
func testAsyncScenario() async throws {
    // Setup
    var detectionTriggered = false
    
    LeakedViewControllerDetector.onDetect(detectionDelay: 0.1) { vc, view, message in
        detectionTriggered = true
        return false
    }
    
    // Action
    // ... create and leak objects
    
    // Wait for detection
    try await Task.sleep(for: .milliseconds(200))
    
    // Verify
    #expect(detectionTriggered == true, "Should detect leak")
}
```

### Memory Leak Simulation
```swift
// Create a leaked view controller
let testVC = TestViewController()
let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
window.rootViewController = testVC
window.makeKeyAndVisible()
window.rootViewController = nil
// testVC is still referenced, creating a leak
```

### Proper Cleanup Testing
```swift
do {
    let testVC = TestViewController()
    // ... use testVC
    // testVC goes out of scope and should be deallocated
}
```

## Performance Considerations

### Test Timing
- Detection delays are kept short (0.1s) for fast test execution
- Longer delays (1.0s+) are only used for specific timing tests
- Total test suite runs in under 30 seconds

### Memory Management
- Tests use weak references where appropriate
- Helper classes implement `deinit` for verification
- Memory pressure tests clean up after themselves

### Concurrency
- All tests are marked `@MainActor` for UI safety
- Concurrent tests use proper synchronization
- Swift 6 concurrency features are thoroughly tested

## Debugging Tests

### Common Issues
1. **Tests timing out**: Increase sleep duration or check detection delay
2. **False positives**: Verify proper cleanup in test setup
3. **Simulator issues**: Reset simulator or try different device

### Debug Techniques
```swift
// Add debug output
LeakedViewControllerDetector.onDetect(detectionDelay: 0.1) { vc, view, message in
    print("🔍 Detected: \(message)")
    return false
}

// Verify object deallocation
class TestViewController: UIViewController {
    deinit {
        print("✅ TestViewController deallocated")
    }
}
```

## Contributing

When adding new tests:

1. **Follow naming conventions**: Use descriptive test names
2. **Add documentation**: Include test purpose and expected behavior
3. **Use appropriate helpers**: Reuse existing helper classes when possible
4. **Test edge cases**: Consider unusual scenarios and error conditions
5. **Verify cleanup**: Ensure tests don't leak memory themselves
6. **Update documentation**: Add new test categories to this README

### Test Template
```swift
@Test("Test description explaining what is being verified")
func testSpecificScenario() async throws {
    // Arrange
    var detectionTriggered = false
    LeakedViewControllerDetector.onDetect(detectionDelay: 0.1) { vc, view, message in
        detectionTriggered = true
        return false
    }
    
    // Act
    // ... perform actions that should/shouldn't trigger detection
    
    // Wait
    try await Task.sleep(for: .milliseconds(200))
    
    // Assert
    #expect(detectionTriggered == expectedResult, "Explanation of expected behavior")
}
```

## Continuous Integration

Tests are designed to run reliably in CI environments:
- No external dependencies
- Deterministic timing
- Proper cleanup
- Clear failure messages

For CI setup, use:
```bash
swift test --destination 'platform=iOS Simulator,name=iPhone 15' --parallel
``` 