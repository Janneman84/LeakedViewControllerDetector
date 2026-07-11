# LeakedViewControllerDetector for UIKit (iOS/tvOS)

[![CI](https://github.com/matheus-gois/LeakedViewControllerDetector/workflows/CI/badge.svg)](https://github.com/matheus-gois/LeakedViewControllerDetector/actions)
[![codecov](https://codecov.io/gh/maatheusgois-dd/LeakedViewControllerDetector/branch/main/graph/badge.svg)](https://codecov.io/gh/maatheusgois-dd/LeakedViewControllerDetector)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![UIKit only](https://img.shields.io/badge/UIKit-red)](https://developer.apple.com/documentation/uikit)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20tvOS-lightgrey.svg)](https://developer.apple.com/documentation/uikit)
[![iOS 13.0+](https://img.shields.io/badge/iOS-13.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![tvOS 13.0+](https://img.shields.io/badge/tvOS-13.0%2B-blue.svg)](https://developer.apple.com/tvos/)
[![Swift Package Manager compatible](https://img.shields.io/badge/spm-compatible-brightgreen.svg?style=flat)](https://swift.org/package-manager)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)


### _Find leaked UIViews and UIViewControllers in real time in your UIKit app without even looking for them!_

Remember having to deal with weird issues in your iOS or tvOS app, that turned out to be caused by some memory leak? No more! LeakedViewControllerDetector helps you find leaked Views and ViewControllers in any UIKit app. Whenever a leak occurs you'll know about it rightaway! Best thing is that you hardly need to make any changes to your code: it's set and forget. It's a great help for every UIKit app!

## Features

- 🔍 **Real-time Detection**: Detects whenever a UIView or UIViewController in your app closes but doesn't deinit
- ⚡ **Instant Alerts**: Shows a warning alert dialog as soon as a leak is detected (in debug builds)
- 📊 **Production Ready**: Works great in release builds too! Log leak warnings to Crashlytics or your analytics service
- 🚀 **Easy Setup**: Set and forget installation with minimal code changes
- ⚡ **Performance Optimized**: Fast and efficient with minimal overhead
- 📱 **Platform Support**: Works on iOS 13.0+ and tvOS 13.0+
- 🎯 **Swift 6.0**: Built with the latest Swift features and concurrency support

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/matheus-gois/LeakedViewControllerDetector.git", from: "1.0.0")
]
```

Or add it through Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/matheus-gois/LeakedViewControllerDetector.git`
3. Select your target and add the package

## Quick Start

<details>
  <summary><b>Basic Setup (Recommended)</b></summary>

Add the import to your `AppDelegate`:
```swift
import LeakedViewControllerDetector
```

Add this code to `application(_:didFinishLaunchingWithOptions:)` in your `AppDelegate`:
```swift
LeakedViewControllerDetector.onDetect() { leakedViewController, leakedView, message in
    #if DEBUG
    print(message)
    return true // Show warning alert dialog
    #else
    // Log warning message to your analytics service (e.g., Crashlytics)
    // CrashlyticsLogger.log(message)
    return false // Don't show warning to users
    #endif
}
```

That's it! The leak detector is now running and will alert you of any memory leaks.
</details>

## Configuration

<details>
  <summary><b>Required Code Changes</b></summary>

Most leak detection works without changing your code. However, a few small changes might be necessary:

### 1. Replace removeFromSuperview()

Replace View's `removeFromSuperview()` with `removeFromSuperviewDetectLeaks()` when you want to ensure a view and its subviews deinitialize:

```swift
// This will warn you if the view or any of its subviews don't deinitialize
someView.removeFromSuperviewDetectLeaks()
```

**Note**: Only use this if the View is supposed to deinit after removal.

### 2. Always Call Super Methods

Ensure you always call `super` in these UIViewController methods:

```swift
override func viewDidLoad() {
    super.viewDidLoad() // Essential!
    // Your code here
}

override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated) // Essential!
    // Your code here
}

override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated) // Essential!
    // Your code here
}
```

### 3. Use removeFromParent() Instead of Array Removal

When removing ViewControllers from container arrays, use `removeFromParent()`:

```swift
// ❌ Don't do this
// navigationController?.viewControllers.remove(at: 3)

// ✅ Do this instead
navigationController?.viewControllers[3].removeFromParent()

// ✅ Same for tab bar controllers
tabBarController?.viewControllers?[3].removeFromParent()
```
</details>

<details>
  <summary><b>Advanced Configuration</b></summary>

### Custom Detection Delay

```swift
LeakedViewControllerDetector.onDetect(detectionDelay: 2.0) { leakedViewController, leakedView, message in
    // Custom delay of 2 seconds before considering something leaked
    return true
}
```

### Ignoring Specific Classes

You can ignore warnings for specific classes by returning `nil`:

```swift
LeakedViewControllerDetector.onDetect() { leakedViewController, leakedView, message in
    // Ignore specific ViewControllers
    if let leakedViewController = leakedViewController {
        if leakedViewController is UIImagePickerController { return nil }
        if leakedViewController is SomeCustomViewController { return nil }
        if type(of: leakedViewController).description().contains("Private") { return nil }
    }
    
    // Ignore specific Views
    if let leakedView = leakedView {
        if leakedView is SomeCustomView { return nil }
        if leakedView.tag == -1 { return nil }
    }
    
    #if DEBUG
    return true
    #else
    return false
    #endif
}
```

### Global Ignore Lists

You can also modify the global ignore lists:

```swift
// Add classes to ignore globally
LeakedViewControllerDetector.ignoredViewControllerClassNames.append("MyCustomViewController")
LeakedViewControllerDetector.ignoredViewClassNames.append("MyCustomView")
LeakedViewControllerDetector.ignoredWindowClassNames.append("MyCustomWindow")
```

### Production Logging Example

```swift
#if DEBUG
let detectionDelay: TimeInterval = 0.5 // Faster detection in debug
#else
let detectionDelay: TimeInterval = 2.0 // More lenient in production
#endif

LeakedViewControllerDetector.onDetect(detectionDelay: detectionDelay) { leakedViewController, leakedView, message in
    #if DEBUG
    print("🚨 Memory Leak Detected: \(message)")
    return true // Show alert in debug
    #else
    // Log to your analytics service
    Analytics.logError("MemoryLeak", parameters: ["message": message])
    
    // Or log to Crashlytics
    let error = NSError(
        domain: Bundle.main.bundleIdentifier ?? "MemoryLeak",
        code: 1001,
        userInfo: [NSLocalizedDescriptionKey: message]
    )
    Crashlytics.crashlytics().record(error: error)
    
    return false // Don't show alerts to users
    #endif
}
```
</details>

## How It Works

<details>
  <summary><b>Detection Mechanism</b></summary>

The detector works by monitoring the lifecycle of ViewControllers and Views:

```swift
override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    
    DispatchQueue.main.asyncAfter(deadline: .now() + detectionDelay) { [weak self] in
        guard let self = self else { return } // If nil, properly deinitialized
        
        // Check if ViewController should have been deallocated
        if self.view.window == nil && 
           self.parent == nil && 
           self.presentedViewController == nil && 
           (view == nil || view.superview == nil) {
            // Leak detected!
        }
    }
}
```

The actual implementation includes additional edge case handling and optimizations.
</details>

## Common Memory Leak Causes

<details>
  <summary><b>Top 10 Memory Leak Patterns</b></summary>

### 1. Strong Reference Cycles in Closures
```swift
// ❌ Creates a retain cycle
DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    print(self.title) // Strong reference to self
}

// ✅ Use weak self
DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
    guard let self = self else { return }
    print(self.title)
}
```

### 2. NotificationCenter Observers
```swift
// ❌ Creates a retain cycle
NotificationCenter.default.addObserver(
    forName: .someNotification,
    object: nil,
    queue: nil
) { notification in
    self.handleNotification() // Strong reference
}

// ✅ Use weak self
NotificationCenter.default.addObserver(
    forName: .someNotification,
    object: nil,
    queue: nil
) { [weak self] notification in
    self?.handleNotification()
}
```

### 3. Strong Delegate References
```swift
// ❌ Strong reference
var delegate: MyDelegate?

// ✅ Weak reference
weak var delegate: MyDelegate?
```

### 4. Timer Retain Cycles
```swift
// ❌ Timer retains target strongly
Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(update), userInfo: nil, repeats: true)

// ✅ Use weak reference or invalidate in deinit
private var timer: Timer?

func startTimer() {
    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
        self?.update()
    }
}

deinit {
    timer?.invalidate()
}
```

### 5. UIAlertController Action Cycles
```swift
// ❌ Alert retains itself
let alert = UIAlertController(title: "Test", message: nil, preferredStyle: .alert)
alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
    print(alert.title) // Retain cycle
})

// ✅ Use unowned or weak
alert.addAction(UIAlertAction(title: "OK", style: .default) { [unowned alert] _ in
    print(alert.title)
})
```

### 6. Presentation Controller Delegate Issues
```swift
// ❌ Can cause leaks in child ViewControllers
self.presentationController?.delegate = self

// ✅ Always set on the presented ViewController
self.presentingViewController?.presentedViewController?.presentationController?.delegate = self
```

### 7. Network Request Callbacks
```swift
// ❌ Network callback retains ViewController
URLSession.shared.dataTask(with: url) { data, response, error in
    DispatchQueue.main.async {
        self.updateUI(with: data) // Strong reference
    }
}.resume()

// ✅ Use weak self
URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
    DispatchQueue.main.async {
        self?.updateUI(with: data)
    }
}.resume()
```

### 8. Animation Completion Blocks
```swift
// ❌ Animation retains ViewController
UIView.animate(withDuration: 1.0, animations: {
    self.view.alpha = 0
}) { _ in
    self.dismiss(animated: true) // Strong reference
}

// ✅ Use weak self
UIView.animate(withDuration: 1.0, animations: { [weak self] in
    self?.view.alpha = 0
}) { [weak self] _ in
    self?.dismiss(animated: true)
}
```

### 9. KVO Observers
```swift
// ❌ Forgetting to remove observers
override func viewDidLoad() {
    super.viewDidLoad()
    someObject.addObserver(self, forKeyPath: "property", options: .new, context: nil)
}

// ✅ Always remove in deinit
deinit {
    someObject.removeObserver(self, forKeyPath: "property")
}
```

### 10. Gesture Recognizer Targets
```swift
// ❌ Can create retain cycles
let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))

// ✅ Remove in deinit or use weak references
deinit {
    view.gestureRecognizers?.forEach { view.removeGestureRecognizer($0) }
}
```
</details>

## Debugging Tips

<details>
  <summary><b>Finding and Fixing Leaks</b></summary>

### Using deinit for Debugging
Add `deinit` methods to track object deallocation:

```swift
class MyViewController: UIViewController {
    deinit {
        print("✅ MyViewController deallocated")
    }
}
```

### Binary Search Debugging
1. Comment out half of your `viewDidLoad` code
2. Test if the leak still occurs
3. Narrow down to the problematic code section
4. Repeat until you find the exact cause

### Memory Graph Debugger
1. Run your app in Xcode
2. Navigate to the leaked screen and back
3. Click the memory graph debugger button
4. Look for objects that should have been deallocated

### Instruments Integration
While this package focuses on ViewControllers and Views, use Instruments for comprehensive memory analysis:
1. Product → Profile
2. Choose "Leaks" instrument
3. Run your app and look for leak patterns
</details>

## Performance Considerations

<details>
  <summary><b>Performance Impact</b></summary>

- **Minimal Overhead**: The detector uses efficient weak references and delayed checks
- **Debug vs Release**: Consider using shorter delays in debug builds for faster feedback
- **Selective Monitoring**: You can disable detection in release builds if needed

```swift
#if DEBUG
LeakedViewControllerDetector.onDetect(detectionDelay: 0.5) { _, _, message in
    print(message)
    return true
}
#endif
```
</details>

## Platform Support

- **iOS**: 13.0+
- **tvOS**: 13.0+
- **Swift**: 6.0+
- **Xcode**: 16.0+

## Limitations

- **SwiftUI**: Not designed for SwiftUI (which has fewer memory leak issues due to its value-type nature)
- **Detection Scope**: Only detects UIViewController and UIView leaks, not other object types
- **False Positives**: May occasionally report false positives in complex scenarios
- **Method Swizzling**: Uses method swizzling on `viewDidAppear`, `viewDidDisappear`, `removeFromParent`, and `showDetailViewController`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by the need for real-time memory leak detection in UIKit apps
- Thanks to the iOS development community for feedback and suggestions
- Special thanks to all contributors who have helped improve this tool

## Support

If you find this package helpful, please consider:
- ⭐ Starring the repository
- 🐛 Reporting issues
- 💡 Suggesting improvements
- 📖 Contributing to documentation

---

**Happy debugging! 🐛🔍**
