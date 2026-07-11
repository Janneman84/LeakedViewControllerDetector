//
//  LeakedViewControllerDetector.swift
//
//  Created by Jan de Vries on 16/04/2022.
//

#if canImport(UIKit)
import Foundation
import UIKit

/**
 Automatically detects and warns you whenever a ViewController in your app closes and it or any of its (sub)views don't deinit.

 Use LeakedViewControllerDetector.onDetect() to start detecting leaks.
 */

@MainActor
public class LeakedViewControllerDetector {
    fileprivate static var callback: (@Sendable (UIViewController?, UIView?, String) -> Bool?)?
    fileprivate static var delay: Double = 1.0
    fileprivate static var warningWindow: UIWindow?
    fileprivate static var lastBackgroundedDate = Date(timeIntervalSince1970: 0)

    /**
     Triggers the callback whenever a leaked ViewController or View is detected.

      - Parameter detectionDelay: The time in seconds allowed for each ViewController or View to deinit itself after it has been closed/removed (i.e. grace period). If it or any of its subviews are still in memory (alive) after the delay the callback will be triggered. Increasing the delay may prevent certain false positives. The default 1.0s is recommended, though a tighter delay may be considered for debug builds.
      - Parameter callback: This will be triggered every time a ViewController closes or View is removed but it or one of its subviews don't deinit. It will trigger again once it does deinit (if ever). It either provides the ViewController or the View that has leaked and a warning message string that you can use to log. The provided ViewController and View will both be nil in case of a deinit warning. Return true to show an alert dialog with the message. Return nil if you want to prevent a future deinit of the ViewController or View from triggering the callback again (useful if you want to ignore warnings of certain ViewControllers/Views).
      */
    public static func onDetect(
        detectionDelay: TimeInterval = 1.0,
        callback: @escaping @Sendable (UIViewController?, UIView?, String) -> Bool?
    ) {
        UIViewController.lvcdSwizzleLifecycleMethods()
        delay = detectionDelay
        self.callback = callback

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    /**
     ViewControllers that belongs to any of these Windows will not be checked for leaks. It contains 2 names by default.
     */
    public static let ignoredWindowClassNames: [String] = [
        "UIRemoteKeyboardWindow",
        "UITextEffectsWindow",
    ]

    /**
     ViewControllers which class is any of these names will not be checked for leaks. It contains a few names by default.
     */
    public static let ignoredViewControllerClassNames: [String] = [
        "UICompatibilityInputViewController",
        "_SFAppPasswordSavingViewController",
        "UIKeyboardHiddenViewController_Save",
        "_UIAlertControllerTextFieldViewController",
        "UISystemInputAssistantViewController",
        "UIPredictionViewController",
    ]

    /**
     Views which class is any of these names will not be checked for leaks. It contains a few names by default.
     */
    public static let ignoredViewClassNames: [String] = [
        "PLTileContainerView",
        "CAMPreviewView",
        "_UIPointerInteractionAssistantEffectContainerView",
    ]

    @objc private static func toBackground() {
        lastBackgroundedDate = Date()
    }
}

public extension UIView {
    /**
     Same as removeFromSuperview() but it also checks if it or any of its subviews don't deinit after the view is removed from the view tree. In that case the LeakedViewControllerDetector warning callback will be triggered.

     Make sure you have set LeakedViewControllerDetector.onDetect(){}, preferably in AppDelegate's application(_:didFinishLaunchingWithOptions:), else it will act the same as regular removeFromSuperview() .

     Only use this method if the view is supposed to deinit shortly after it is removed from the view tree, or else it may trigger false warnings. In that case use regular removeFromSuperview() instead.

      */
    @objc func removeFromSuperviewDetectLeaks() {
        let superViewWasNil = superview == nil && window == nil // check if view was removed already
        removeFromSuperview()

        // only check when app is active for now
        // callback may be nil on purpose, e.g. for release builds, so just ignore then
        if
            LeakedViewControllerDetector.callback != nil, !superViewWasNil,
            UIApplication.shared.applicationState == .active
        {
            checkForLeakedSubViews()
        }
    }
}

private extension UIView {
    @objc func checkForLeakedSubViews() {
        let delay = LeakedViewControllerDetector.delay

        iterateTopSubviews { topSubview in
            let startTime = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak topSubview, weak self] in
                if
                    self == nil || self?.superview == nil,
                    self?.firstViewController == nil, // in case it switched VC
                    let leakedView = topSubview?.rootView,
                    leakedView == topSubview || !(leakedView is UIWindow), // prevents rare crash
                    leakedView.firstViewController == nil, // prevents false positives
                    objc_getAssociatedObject(leakedView, &LVCDDeallocator.key) == nil,
                    UIApplication.shared.applicationState == .active,
                    // theoretically not needed when also checking lastBackgroundedDate, but just in case
                    LeakedViewControllerDetector.lastBackgroundedDate < startTime,
                    !LeakedViewControllerDetector.ignoredViewClassNames.contains(type(of: leakedView).description())
                {
                    let errorTitle = "VIEW STILL IN MEMORY"
                    var errorMessage = leakedView.debugDescription.lvcdRemoveBundleAndModuleName()
                    if let bundleName = Bundle.main.infoDictionary?["CFBundleName"] {
                        errorMessage = errorMessage.replacingOccurrences(of: "\(bundleName).", with: "")
                    }
                    let showAlert = LeakedViewControllerDetector.callback?(
                        nil,
                        leakedView,
                        "\(errorTitle) \(errorMessage)"
                    )
                    var screenshot: UIImage?
                    if showAlert ?? false {
                        screenshot = leakedView.makeScreenshot()
                        UIViewController.lvcdShowWarningAlert(
                            errorTitle: errorTitle,
                            errorMessage: errorMessage,
                            objectIdentifier: Int(bitPattern: ObjectIdentifier(leakedView)),
                            screenshot: screenshot
                        )
                    }

                    if showAlert != nil {
                        let deallocator = LVCDDeallocator()
                        deallocator.memoryLeakDetectionDate = Date().timeIntervalSince1970 - delay
                        deallocator.errorMessage = errorMessage
                        deallocator.objectIdentifier = Int(bitPattern: ObjectIdentifier(leakedView))
                        deallocator.objectType = "VIEW"
                        deallocator.subviews = leakedView.subviews
                        deallocator.weakView = leakedView
                        deallocator.screenshot = screenshot
                        objc_setAssociatedObject(
                            leakedView,
                            &LVCDDeallocator.key,
                            deallocator,
                            .OBJC_ASSOCIATION_RETAIN
                        )
                    }
                }
            }
        }
    }

    func makeScreenshot() -> UIImage? {
        let fvc = firstViewController
        if let fvc, fvc.view == self {
            // UIImagePickerController is not available in tvOS so do OS check
            #if os(iOS)
            if fvc is UIImagePickerController {
                return nil // screenshotting UIIPC is not possible and can even lead to a permanent memory leak,
                // PHPicker works fine though
            }
            #endif
        }

        // create centered checkerboard background pattern image
        let squareSize: CGFloat = 20
        let offset = CGPoint(
            x: frame.width.truncatingRemainder(dividingBy: squareSize) * 0.5,
            y: frame.height.truncatingRemainder(dividingBy: squareSize) * 0.5
        )
        let checkerBoard = UIView(frame: .init(x: 0, y: 0, width: squareSize * 2, height: squareSize * 2))
        checkerBoard.backgroundColor = .init(white: 1 - 0.4 * 0.5, alpha: 1)
        for point in [
            CGPoint(x: 0 as CGFloat, y: 0 as CGFloat),
            CGPoint(x: -squareSize, y: squareSize),
            CGPoint(x: squareSize, y: squareSize),
            CGPoint(x: 0 as CGFloat, y: squareSize * 2),
        ] {
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = UIBezierPath(rect: .init(
                x: point.x + offset.x,
                y: point.y - offset.y,
                width: squareSize,
                height: squareSize
            )).cgPath
            shapeLayer.fillColor = UIColor(white: 1 - 0.6 * 0.5, alpha: 1).cgColor
            checkerBoard.layer.addSublayer(shapeLayer)
        }

        let checkerBoardImage: UIImage
        if #available(iOS 10.0, *) {
            let renderer = UIGraphicsImageRenderer(size: checkerBoard.bounds.size)
            checkerBoardImage = renderer.image { _ in
                checkerBoard.drawHierarchy(in: checkerBoard.bounds, afterScreenUpdates: true)
            }
        } else {
            UIGraphicsBeginImageContextWithOptions(checkerBoard.bounds.size, false, 0)
            checkerBoard.drawHierarchy(in: checkerBoard.bounds, afterScreenUpdates: true)
            checkerBoardImage = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
            UIGraphicsEndImageContext()
        }

        let wasAlpha = alpha
        let wasHidden = isHidden
        alpha = alpha < 0.1 ? 1.0 : alpha // useful for alerts
        isHidden = false
        var wasTARMICS = [ObjectIdentifier: Bool]()
        var cornerRadius: CGFloat = 0

        // stick to two levels for now, seems to work best without constraint warnings
        // level 3 is necessary for getting UIAlert radius
        iterateSubviews(maxLevel: 3) { subview, level in
            if !(subview is UINavigationBar || subview is UICollectionViewCell || subview is UITabBar || level > 2) {
                wasTARMICS[ObjectIdentifier(subview)] = subview.translatesAutoresizingMaskIntoConstraints
                subview.translatesAutoresizingMaskIntoConstraints = true
            }
            if cornerRadius == 0, subview.bounds == bounds, subview.layer.cornerRadius != 0 {
                cornerRadius = subview.layer.cornerRadius
            }
            return true
        }

        let container = UIView(frame: .init(origin: .zero, size: frame.size))
        container.addSubview(self)
        objc_setAssociatedObject(
            container,
            &LVCDDeallocator.key,
            LVCDDeallocator(),
            .OBJC_ASSOCIATION_RETAIN
        ) // prevents triggering warnings itself

        let shapeLayer = CAShapeLayer()
        shapeLayer.path = UIBezierPath(rect: frame).cgPath
        shapeLayer.fillColor = UIColor(patternImage: checkerBoardImage).withAlphaComponent(0.5).cgColor
        container.layer.insertSublayer(shapeLayer, at: 0)

        // check for subviews sticking out its bounds, forget about the same for sublayers for now
        var unclippedFrame = frame
        iterateSubviews { subview, _ in
            if subview.isHidden || subview.alpha < 0.1 {
                return false
            }

            var alpha: CGFloat = 0
            subview.backgroundColor?.getRed(nil, green: nil, blue: nil, alpha: &alpha)

            if subview.frame.size.height * subview.frame.size.width != 0, alpha >= 0.1 {
                unclippedFrame = unclippedFrame.union(subview.convert(subview.bounds, to: container))
            }
            return !subview.clipsToBounds && !subview.layer.masksToBounds && !(subview is UIScrollView)
        }

        guard unclippedFrame.size.width > 0, unclippedFrame.size.height > 0 else { return nil }

        let container2 = UIView(frame: .init(origin: .zero, size: unclippedFrame.size))
        container2.backgroundColor = UIColor.white.withAlphaComponent(0.03)
        container2.addSubview(container)
        container.frame = .init(
            x: 0 - unclippedFrame.minX,
            y: 0 - unclippedFrame.minY,
            width: unclippedFrame.width,
            height: unclippedFrame.height
        )
        container2.layer.cornerRadius = cornerRadius
        container2.layer.masksToBounds = container2.layer.cornerRadius > 0
        objc_setAssociatedObject(
            container2,
            &LVCDDeallocator.key,
            LVCDDeallocator(),
            .OBJC_ASSOCIATION_RETAIN
        ) // prevents triggering warnings itself

        var iosOnMac = false
        if #available(iOS 13, tvOS 13, *) {
            iosOnMac = ProcessInfo.processInfo.isMacCatalystApp
        }
        let maxWidth: CGFloat = 240 - (iosOnMac ? 12 : 0) // hard coded width for now
        let imageSize = container2.frame.width <= maxWidth
            ? container2.frame.size
            : CGSize(
                width: maxWidth,
                height: maxWidth * (container2.frame.height / container2.frame.width)
            )

        let image: UIImage?
        if #available(iOS 10.0, *) {
            let imageRenderer = UIGraphicsImageRenderer(size: imageSize)
            image = imageRenderer.image { _ in
                container2.drawHierarchy(
                    in: CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height),
                    afterScreenUpdates: true
                )
            }
        } else {
            UIGraphicsBeginImageContextWithOptions(imageSize, false, 0)
            container2.drawHierarchy(
                in: CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height),
                afterScreenUpdates: true
            )
            image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
        }

        // restore values just in case
        alpha = wasAlpha
        isHidden = wasHidden
        iterateSubviews { subview, level in
            if !(subview is UINavigationBar || subview is UICollectionViewCell || subview is UITabBar || level > 2) {
                subview.translatesAutoresizingMaskIntoConstraints = wasTARMICS[ObjectIdentifier(subview)] ?? subview
                    .translatesAutoresizingMaskIntoConstraints
            }
            return true
        }

        return image
    }

    func iterateTopSubviews(onViewFound: (UIView) -> Void) {
        var hasSubview = false

        if !(self is UINavigationBar && firstViewController is UINavigationController) {
            for subview in subviews {
                subview.iterateTopSubviews(onViewFound: onViewFound)
                hasSubview = true
            }
        }
        if !hasSubview {
            onViewFound(self)
        }
    }

    func iterateSubviews(maxLevel: UInt = UInt.max, level: UInt = 0, onSubview: (UIView, UInt) -> (Bool)) {
        if onSubview(self, level) {
            let level = level + 1
            if level <= maxLevel {
                for subview in subviews {
                    subview.iterateSubviews(maxLevel: maxLevel, level: level, onSubview: onSubview)
                }
            }
        }
    }

    var rootView: UIView {
        superview?.rootView ?? self
    }

    var firstViewController: UIViewController? {
        sequence(first: self, next: { $0.next }).first(where: { $0 is UIViewController }) as? UIViewController
    }
}

private extension UIViewController {
    static let lvcdCheckForMemoryLeakNotification = Notification.Name("lvcdCheckForMemoryLeak")
    static let lvcdCheckForSplitViewVCMemoryLeakNotification = Notification.Name("lvcdCheckForSplitViewVCMemoryLeak")

    static func lvcdSwizzleLifecycleMethods() {
        lvcdActuallySwizzleLifecycleMethods // this makes sure it can only swizzle once
    }

    private static let lvcdActuallySwizzleLifecycleMethods: Void = {
        let originalVdaMethod = class_getInstanceMethod(UIViewController.self, #selector(viewDidLoad))
        let swizzledVdaMethod = class_getInstanceMethod(UIViewController.self, #selector(lvcdViewDidLoad))
        method_exchangeImplementations(originalVdaMethod!, swizzledVdaMethod!)

        let originalVddMethod = class_getInstanceMethod(UIViewController.self, #selector(viewDidDisappear(_:)))
        let swizzledVddMethod = class_getInstanceMethod(UIViewController.self, #selector(lvcdViewDidDisappear(_:)))
        method_exchangeImplementations(originalVddMethod!, swizzledVddMethod!)

        let originalRfpMethod = class_getInstanceMethod(UIViewController.self, #selector(removeFromParent))
        let swizzledRfpMethod = class_getInstanceMethod(UIViewController.self, #selector(lvcdRemoveFromParent))
        method_exchangeImplementations(originalRfpMethod!, swizzledRfpMethod!)

        let originalSdvcMethod = class_getInstanceMethod(
            UISplitViewController.self,
            #selector(showDetailViewController(_:sender:))
        )
        let swizzledSdvcMethod = class_getInstanceMethod(
            UIViewController.self,
            #selector(lvcdShowDetailViewController(_:sender:))
        )
        method_exchangeImplementations(originalSdvcMethod!, swizzledSdvcMethod!)

        let originalSvMethod = class_getInstanceMethod(UIViewController.self, #selector(setter: view))
        let swizzledSvMethod = class_getInstanceMethod(UIViewController.self, #selector(lvcdSetView(_:)))
        method_exchangeImplementations(originalSvMethod!, swizzledSvMethod!)
    }()

    func lvcdShouldIgnore() -> Bool {
        LeakedViewControllerDetector.ignoredViewControllerClassNames.contains(type(of: self).description())
            ||
            (isViewLoaded && view?.window != nil && LeakedViewControllerDetector.ignoredWindowClassNames
                .contains(type(of: view.window!).description())
            )
            || objc_getAssociatedObject(self, &LVCDSplitViewAssociatedObject.key) != nil
    }

    @objc private func lvcdSetView(_ newView: UIView?) {
        if isViewLoaded, let deallocator = objc_getAssociatedObject(self, &LVCDDeallocator.key) as? LVCDDeallocator {
            deallocator.strongView?.checkForLeakedSubViews()
            deallocator.strongView = newView
        }
        lvcdSetView(newView)
    }

    @objc private func lvcdViewDidLoad() {
        lvcdViewDidLoad() // run original implementation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            if !lvcdShouldIgnore() {
                if objc_getAssociatedObject(self, &LVCDDeallocator.key) == nil {
                    objc_setAssociatedObject(
                        self,
                        &LVCDDeallocator.key,
                        LVCDDeallocator(view),
                        .OBJC_ASSOCIATION_RETAIN
                    )
                }
                addCheckForMemoryLeakObserver(skipIgnoreCheck: true)
            }
        }
    }

    func addCheckForMemoryLeakObserver(skipIgnoreCheck: Bool = false) {
        NotificationCenter.lvcd.removeObserver(
            self,
            name: UIViewController.lvcdCheckForMemoryLeakNotification,
            object: nil
        )
        if skipIgnoreCheck || !lvcdShouldIgnore() {
            NotificationCenter.lvcd.addObserver(
                self,
                selector: #selector(lvcdCheckForMemoryLeak),
                name: UIViewController.lvcdCheckForMemoryLeakNotification,
                object: nil
            )
        }
    }

    @objc private func lvcdViewDidDisappear(_ animated: Bool) {
        lvcdViewDidDisappear(animated) // run original implementation

        // ignore parent VCs because one of their children will trigger viewDidDisappear() too
        if
            (self as? UINavigationController)?.viewControllers.isEmpty ?? true,
            (self as? UITabBarController)?.viewControllers?.isEmpty ?? true,
            (self as? UIPageViewController)?.viewControllers?.isEmpty ?? true,
            !lvcdShouldIgnore()
        {
            NotificationCenter.lvcd.post(name: Self.lvcdCheckForMemoryLeakNotification, object: nil)
        }
    }

    @objc private func lvcdRemoveFromParent() {
        lvcdRemoveFromParent() // run original implementation
        if !lvcdShouldIgnore(), view?.window != nil {
            NotificationCenter.lvcd.post(name: Self.lvcdCheckForMemoryLeakNotification, object: nil)
        }
    }

    @objc private func lvcdShowDetailViewController(_ vc: UIViewController, sender: Any?) {
        NotificationCenter.lvcd.post(name: Self.lvcdCheckForSplitViewVCMemoryLeakNotification, object: self)
        NotificationCenter.lvcd.post(name: Self.lvcdCheckForMemoryLeakNotification, object: nil)

        if objc_getAssociatedObject(vc, &LVCDSplitViewAssociatedObject.key) == nil {
            let mldAssociatedObject = LVCDSplitViewAssociatedObject()
            mldAssociatedObject.splitViewController = self as? UISplitViewController
            mldAssociatedObject.viewController = vc
            objc_setAssociatedObject(
                vc,
                &LVCDSplitViewAssociatedObject.key,
                mldAssociatedObject,
                .OBJC_ASSOCIATION_RETAIN
            )
        }
        lvcdShowDetailViewController(vc, sender: sender) // run original implementation
    }

    @MainActor
    static var lvcdMemoryCheckQueue = Set<ObjectIdentifier>()

    var lvcdRootParentViewController: UIViewController {
        parent?.lvcdRootParentViewController ?? self
    }

    @objc private func lvcdCheckForMemoryLeak(restarted: Bool = false) {
        // only check when active for now
        guard UIApplication.shared.applicationState == .active else {
            return
        }

        if (view != nil && view.window != nil) || lvcdShouldIgnore() {
            return
        }

        let objectIdentifier = ObjectIdentifier(self)

        // in some cases lvcdCheckForMemoryLeakNotification may be called multiple times at once, this guard prevents
        // double checking
        guard !Self.lvcdMemoryCheckQueue.contains(objectIdentifier) else { return }
        Self.lvcdMemoryCheckQueue.insert(objectIdentifier)

        DispatchQueue.main.async { [self] in
            Self.lvcdMemoryCheckQueue.remove(objectIdentifier)
            let rootParentVC = lvcdRootParentViewController
            guard
                rootParentVC.presentedViewController == nil,
                !isViewLoaded || rootParentVC.view.window == nil,
                let deallocator = objc_getAssociatedObject(self, &LVCDDeallocator.key) as? LVCDDeallocator,
                deallocator.objectIdentifier == 0
            else { return }

            if let svc = self as? UISplitViewController {
                NotificationCenter.lvcd.post(name: Self.lvcdCheckForSplitViewVCMemoryLeakNotification, object: svc)
            }

            let startTime = Date()

            let delay = LeakedViewControllerDetector.delay
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                // if self is nil it deinitted, so no memory leak
                guard let self else { return }

                // if backgrounded now or during the delay ignore for now
                if
                    UIApplication.shared.applicationState != .active || LeakedViewControllerDetector
                        .lastBackgroundedDate > startTime
                {
                    return
                }

                // if somehow this asyncAfter code is executed way too late restart just in case
                if !restarted, abs(startTime.timeIntervalSinceNow) > (delay + 0.5) {
                    lvcdCheckForMemoryLeak(restarted: true)
                    return
                }

                // these conditions constitute a 'limbo' ViewController, i.e. a memory leak:
                if
                    !isViewLoaded || view?.window == nil, parent == nil,
                    presentedViewController == nil,
                    view == nil || view.superview == nil || type(of: view.rootView)
                        .description() == "UILayoutContainerView"
                {
                    // once warned don't warn again
                    NotificationCenter.lvcd.removeObserver(
                        self,
                        name: Self.lvcdCheckForMemoryLeakNotification,
                        object: nil
                    )
                    let errorTitle = "VIEWCONTROLLER STILL IN MEMORY"
                    var errorMessage = debugDescription.lvcdRemoveBundleAndModuleName()

                    // add children's names to the message in case of NavVC or TabVC for easier identification
                    if let nvc = self as? UINavigationController {
                        errorMessage = "\(errorMessage):\n\(nvc.viewControllers)"
                    }
                    if let tbvc = self as? UITabBarController, let vcs = tbvc.viewControllers {
                        errorMessage = "\(errorMessage):\n\(vcs)"
                    }
                    // add alert title/message to the message for easier identification
                    if let alertVC = self as? UIAlertController {
                        var actions = alertVC.actions.isEmpty ? "-" : ""
                        for action in alertVC.actions {
                            actions = "\(actions) \"\(action.title ?? "-")\","
                        }

                        let title = (alertVC.title ?? "").isEmpty ? "" : alertVC.title!
                        let message = (alertVC.message ?? "").isEmpty ? "" : alertVC.message!
                        errorMessage = "\(errorMessage)\n title: \"\(title)\";\nmessage: \"\(message)\";\nactions: \(actions);"

                        if !(alertVC.textFields ?? []).isEmpty {
                            var tfs = ""
                            for tf in alertVC.textFields ?? [] {
                                tfs = "\(tfs) \"\(tf.placeholder ?? "-")\","
                            }
                            errorMessage += "\ntextfields: \(tfs);"
                        }

                        errorMessage = errorMessage.replacingOccurrences(of: ",;", with: ";")
                    }
                    let showAlert = LeakedViewControllerDetector.callback?(self, nil, "\(errorTitle) \(errorMessage)")
                    var screenshot: UIImage?
                    if showAlert ?? false {
                        screenshot = view?.rootView.makeScreenshot()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            Self.lvcdShowWarningAlert(
                                errorTitle: errorTitle,
                                errorMessage: errorMessage,
                                objectIdentifier: Int(bitPattern: ObjectIdentifier(self)),
                                screenshot: screenshot
                            )
                        }
                    }

                    if showAlert != nil {
                        deallocator.memoryLeakDetectionDate = Date().timeIntervalSince1970 - delay
                        deallocator.errorMessage = errorMessage
                        deallocator.objectIdentifier = Int(bitPattern: ObjectIdentifier(self))
                        deallocator.objectType = "VIEWCONTROLLER"
                        deallocator.screenshot = screenshot
                    }
                }
            }
        }
    }

    // call this if VC deinits, if memory leak was detected earlier it apparently resolved itself, so notify this:
    @MainActor
    class func lvcdMemoryLeakResolved(
        memoryLeakDetectionDate: TimeInterval,
        errorMessage: String,
        objectIdentifier: Int,
        objectType: String,
        screenshot: UIImage?
    ) {
        let interval = Date().timeIntervalSince1970 - memoryLeakDetectionDate

        let errorTitle = "LEAKED \(objectType) DEINNITED"
        let errorMessage = String(format: "\(errorMessage)\n\nDeinnited after %.3fs.", interval)

        if LeakedViewControllerDetector.callback?(nil, nil, "\(errorTitle) \(errorMessage)") ?? false {
            Self.lvcdShowWarningAlert(
                errorTitle: errorTitle,
                errorMessage: errorMessage,
                resolved: true,
                objectIdentifier: objectIdentifier,
                screenshot: screenshot
            )
        }
    }

    @MainActor
    static var lvcdAlertQueue = [LVCDAlertController]()

    @MainActor
    class func lvcdShowWarningAlert(
        errorTitle: String?,
        errorMessage: String?,
        resolved: Bool = false,
        objectIdentifier: Int,
        screenshot: UIImage? = nil
    ) {
        var iosOnMac = false
        if #available(iOS 13, tvOS 13, *) {
            iosOnMac = ProcessInfo.processInfo.isMacCatalystApp
        }

        let alert = LVCDAlertController(
            title: errorTitle,
            message: errorMessage,
            preferredStyle: UIAlertController.Style.alert
        )
        alert.preferredWindowColor = resolved
            ? UIColor.systemTeal.withAlphaComponent(0.30)
            : UIColor.systemPink.withAlphaComponent(0.25)
        alert.view.tag = objectIdentifier
        alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.cancel) { _ in
            if LeakedViewControllerDetector.warningWindow?.rootViewController?.presentedViewController == nil {
                LeakedViewControllerDetector.warningWindow = nil
            }
        })
        alert.preferredAction = alert.actions.first!

        if let screenshot {
            let maxWidth: CGFloat = 240 - (iosOnMac ? 12 : 0) // alert content width hard coded for now

            // create and position imageview and set checkboard background and screenshot
            let imageView = UIImageView(frame: CGRect(
                x: (maxWidth - min(maxWidth, screenshot.size.width)) * 0.5,
                y: 0,
                width: min(maxWidth, screenshot.size.width),
                height: min(screenshot.size.height, maxWidth * (screenshot.size.height / screenshot.size.width))
            ))
            imageView.contentMode = .scaleAspectFit
            imageView.image = screenshot
            imageView.clipsToBounds = false
            imageView.layer.shadowColor = UIColor.black.cgColor
            imageView.layer.shadowOpacity = 0.15
            imageView.layer.shadowOffset = .init(width: 0, height: 0.5)
            imageView.layer.shadowRadius = 2
            imageView.transform = CGAffineTransform(translationX: iosOnMac ? -14 : 0, y: 2)

            // abuse textfield to add the imageview to the alert
            alert.addTextField { tf in
                tf.isUserInteractionEnabled = false
                if let superDuper = tf.superview?.superview {
                    tf.translatesAutoresizingMaskIntoConstraints = false
                    let height = superDuper.heightAnchor.constraint(equalToConstant: imageView.frame.height + 6)
                    height.priority = .defaultHigh
                    for view in superDuper.subviews {
                        view.isHidden = true
                    }
                    superDuper.addConstraint(height)
                    superDuper.addSubview(imageView)
                }
            }
        }
        lvcdShowWarningAlert(alert)
    }

    @MainActor
    class func lvcdShowWarningAlert(_ alert: LVCDAlertController?) {
        guard let alert else { return }
        if let warningWindow = LeakedViewControllerDetector.warningWindow {
            if
                let tagAlertController = UIApplication.lvcdFindViewControllerWithTag(
                    controller: warningWindow.rootViewController,
                    tag: alert.view.tag
                ) as? LVCDAlertController, !tagAlertController.isBeingDismissed
            {
                tagAlertController.title = alert.title
                tagAlertController.message = alert.message
                tagAlertController.view.transform = .init(scaleX: 0.9, y: 1.125)
                tagAlertController.preferredWindowColor = alert.preferredWindowColor
//                tagAlertController.view.alpha = 0.0
                UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseOut) {
                    tagAlertController.view.transform = .init(scaleX: 1.0, y: 1.0)
//                    tagAlertController.view.alpha = 1.0
                }
            } else if
                let topViewController = UIApplication
                    .lvcdTopViewController(controller: warningWindow.rootViewController)
            {
                if topViewController.isBeingPresented || topViewController.isBeingDismissed {
                    lvcdAlertQueue.insert(alert, at: 0)
                } else {
                    topViewController.present(alert, animated: lvcdAlertQueue.count < 2) {
                        lvcdShowWarningAlert(lvcdAlertQueue.popLast())
                    }
                }
            } else {
                assertionFailure("No ViewController found to present warning alert dialog on.")
            }
        } else {
            if #available(iOS 13, tvOS 13, *) {
                if
                    let windowScene = UIApplication.lvcdTopViewController()?.view?.window?.windowScene ?? UIApplication
                        .shared.lvcdFirstActiveWindowScene
                {
                    LeakedViewControllerDetector.warningWindow = UIWindow(windowScene: windowScene)
                } else {
                    assertionFailure("No WindowScene found to present warning alert dialog on.")
                }
            } else {
                LeakedViewControllerDetector.warningWindow = UIWindow(frame: UIScreen.main.bounds)
            }

            if let warningWindow = LeakedViewControllerDetector.warningWindow {
                warningWindow.rootViewController = LVCDViewController()
                warningWindow.windowLevel = .alert
                warningWindow.makeKeyAndVisible()
                warningWindow.backgroundColor = .clear
                UIView.animate(withDuration: 0.25) {
                    warningWindow.backgroundColor = UIColor.systemPink.withAlphaComponent(0.25)
                }
                warningWindow.rootViewController?.present(alert, animated: true) {
                    lvcdShowWarningAlert(lvcdAlertQueue.popLast())
                }
            }
        }
    }

    class LVCDViewController: UIViewController {
        override func viewDidAppear(_: Bool) {
            // purposely not calling super here so it won't trigger a warning itself
        }

        override func viewDidDisappear(_: Bool) {
            // purposely not calling super here so it won't trigger a warning itself
        }
    }

    class LVCDAlertController: UIAlertController {
        override func viewDidAppear(_: Bool) {
            // purposely not calling super here so it won't trigger a warning itself
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if LeakedViewControllerDetector.warningWindow?.rootViewController == presentingViewController {
                UIView.animate(withDuration: 0.25, delay: 0) {
                    LeakedViewControllerDetector.warningWindow?.alpha = 0.0
                }
            } else {
                updateWindowColor(disappearing: true)
            }
        }

        override func viewDidDisappear(_: Bool) {
            // purposely not calling super here so it won't trigger a warning itself

            // failsafe in case somehow window doesn't go away you can at least see it
            DispatchQueue.main.async {
                LeakedViewControllerDetector.warningWindow?.alpha = 1.0
            }
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            updateWindowColor()
        }

        var preferredWindowColor: UIColor = .clear { didSet {
            updateWindowColor()
        }}

        func updateWindowColor(disappearing: Bool = false) {
            if
                let ww = LeakedViewControllerDetector.warningWindow,
                let topAlertController = UIApplication
                    .lvcdTopViewController(controller: ww.rootViewController) as? LVCDAlertController
            {
                var alertController = topAlertController
                if
                    disappearing,
                    let presentingVC = topAlertController.presentingViewController as? LVCDAlertController
                {
                    alertController = presentingVC
                }
                if ww.backgroundColor != alertController.preferredWindowColor {
                    UIView.animate(withDuration: 0.15) {
                        ww.backgroundColor = alertController.preferredWindowColor
                    }
                }
            }
        }
    }

    @MainActor
    class LVCDSplitViewAssociatedObject {
        nonisolated(unsafe) static var key = malloc(1)!

        weak var splitViewController: UISplitViewController?
        weak var viewController: UIViewController? { didSet {
            NotificationCenter.lvcd.addObserver(
                self,
                selector: #selector(checkIfBelongsToSplitViewController(_:)),
                name: UIViewController.lvcdCheckForSplitViewVCMemoryLeakNotification,
                object: nil
            )
        }}

        @objc func checkIfBelongsToSplitViewController(_ notification: Notification) {
            if
                notification.object as? UISplitViewController == splitViewController,
                let viewController
            {
                objc_setAssociatedObject(
                    viewController,
                    &LVCDSplitViewAssociatedObject.key,
                    nil,
                    .OBJC_ASSOCIATION_RETAIN
                )
                if objc_getAssociatedObject(viewController, &LVCDDeallocator.key) == nil {
                    objc_setAssociatedObject(
                        viewController,
                        &LVCDDeallocator.key,
                        LVCDDeallocator(viewController.view),
                        .OBJC_ASSOCIATION_RETAIN
                    )
                }
                viewController.addCheckForMemoryLeakObserver()
                DispatchQueue.main.asyncAfter(deadline: .now() + LeakedViewControllerDetector.delay) { [
                    weak splitViewController,
                    weak viewController
                ] in
                    if splitViewController == nil {
                        viewController?.lvcdCheckForMemoryLeak()
                    }
                }
            }
        }
    }
}

private extension NotificationCenter {
    static let lvcd = NotificationCenter()
}

@MainActor
private class LVCDDeallocator {
    nonisolated(unsafe) static var key = malloc(1)!

    var memoryLeakDetectionDate: TimeInterval = 0.0
    var errorMessage = ""
    var objectIdentifier = 0
    var objectType = ""
    var screenshot: UIImage?

    // used by ViewController
    var strongView: UIView?

    // used by View
    var subviews: [UIView]?
    var subviewObserver: NSKeyValueObservation?
    weak var weakView: UIView? { didSet {
        subviewObserver?.invalidate()
        subviewObserver = weakView?.layer.observe(\.sublayers, options: [.old, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                if let view = self?.weakView {
                    self?.subviews = view.subviews
                }
            }
        }
        // using observer allows to keep track of subviews during leak without themselves leaking
        // if leaked view clears it can then check its current subviews for leaks
    }}

    init(_ view: UIView? = nil) {
        strongView = view
    }

    deinit {
        let strongView = self.strongView
        let subviews = self.subviews
        let objectIdentifier = self.objectIdentifier
        let memoryLeakDetectionDate = self.memoryLeakDetectionDate
        let errorMessage = self.errorMessage
        let objectType = self.objectType
        let screenshot = self.screenshot

        if strongView != nil || !(subviews ?? []).isEmpty || objectIdentifier != 0 {
            DispatchQueue.main.async {
                // ViewController
                strongView?.checkForLeakedSubViews()

                // View
                for subview in subviews ?? [] {
                    subview.checkForLeakedSubViews()
                }

                if objectIdentifier != 0 {
                    UIViewController.lvcdMemoryLeakResolved(
                        memoryLeakDetectionDate: memoryLeakDetectionDate,
                        errorMessage: errorMessage,
                        objectIdentifier: objectIdentifier,
                        objectType: objectType,
                        screenshot: screenshot
                    )
                }
            }
        }

        subviewObserver?.invalidate()
    }
}

private extension UIResponder {
    var viewController: UIViewController? {
        next as? UIViewController ?? next?.viewController
    }
}

private extension UIApplication {
    /// get a window, preferably once that is in foreground (active) in case you have multiple windows on iPad
    var lvcdActiveMainKeyWindow: UIWindow? {
        if #available(iOS 13, tvOS 13, *) {
            let activeScenes = connectedScenes.filter { $0.activationState == UIScene.ActivationState.foregroundActive }
            return (!activeScenes.isEmpty ? activeScenes : connectedScenes)
                .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
                .first { $0.isKeyWindow }
        } else {
            return keyWindow
        }
    }

    class func lvcdTopViewController(controller: UIViewController? = UIApplication.shared.lvcdActiveMainKeyWindow?
        .rootViewController
    )
        -> UIViewController?
    {
        controller?.presentedViewController != nil
            ? lvcdTopViewController(controller: controller!.presentedViewController!)
            : controller
    }

    class func lvcdFindViewControllerWithTag(
        controller: UIViewController? = UIApplication.shared.lvcdActiveMainKeyWindow?.rootViewController,
        tag: Int
    )
        -> UIViewController?
    {
        controller == nil
            ? nil
            : (controller!.view.tag == tag
                ? controller!
                : lvcdFindViewControllerWithTag(
                    controller: controller!.presentedViewController,
                    tag: tag
                )
            )
    }

    @available(iOS 13.0, tvOS 13, *)
    var lvcdFirstActiveWindowScene: UIWindowScene? {
        let activeScenes = UIApplication.shared.connectedScenes
            .filter { $0.activationState == UIScene.ActivationState.foregroundActive && $0 is UIWindowScene }
        return (!activeScenes.isEmpty ? activeScenes : UIApplication.shared.connectedScenes)
            .first(where: { $0 is UIWindowScene }) as? UIWindowScene
    }
}

private extension String {
    private mutating func lvcdRegReplace(pattern: String, replaceWith: String = "") {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines])
            let range = NSRange(startIndex..., in: self)
            self = regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: replaceWith)
        } catch { return }
    }

    private nonisolated(unsafe) static var lvcdBundleName: String?
    private nonisolated(unsafe) static var lvcdModuleName: String?

    func lvcdRemoveBundleAndModuleName() -> String {
        Self.lvcdBundleName = Self.lvcdBundleName ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
        if Self.lvcdBundleName != nil, Self.lvcdModuleName == nil {
            Self.lvcdModuleName = Self.lvcdBundleName
            Self.lvcdModuleName?.lvcdRegReplace(pattern: "[^A-Za-z0-9]", replaceWith: "_")
        }
        if Self.lvcdBundleName != nil, Self.lvcdModuleName != nil {
            return replacingOccurrences(of: "\(Self.lvcdBundleName!).", with: "")
                .replacingOccurrences(of: "\(Self.lvcdModuleName!).", with: "")
        }
        return self
    }
}

#endif
