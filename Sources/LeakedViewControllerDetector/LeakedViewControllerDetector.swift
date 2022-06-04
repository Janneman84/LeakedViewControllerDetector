//
//  LeakedViewControllerDetector.swift
//
//  Created by Jan de Vries on 16/04/2022.
//

import UIKit

/**
Automatically detects and warns you whenever a ViewController in your app closes and it or one of its Views don't deinit.
 
Use LeakedViewControllerDetector.onDetect() to start detecting leaks.
*/

public class LeakedViewControllerDetector {
    
    fileprivate static var callback: ((UIViewController?, UIView?, String)->Bool?)?
    fileprivate static var delay: Double = 1.0
    fileprivate static var warningWindow: UIWindow?

    /**
    Triggers the callback whenever a leaked ViewController or View is detected.
    
     - Parameter debugDelay: The time in seconds allowed for each ViewController to deinit itself after it has closed. If it or any of its views are still in memory after the delay the callback will be triggered. Increasing the delay may prevent certain false positives. This value is only used for builds flagged with DEBUG, for release build the value of releaseDelay is used.
     - Parameter releaseDelay: Same as debugDelay but this value is used for release builds.
     - Parameter callback: This will be triggered every time a ViewController closes but it or one of its views don't deinit. It will trigger again once it does deinit (if ever). It either provides the ViewController or the View that has leaked and a warning message string that you can use to log. The provided ViewController and View will both be nil in case of a deinit warning. Return true to show an alert dialog with the message. Return nil if you want to prevent a future deinit of the ViewController or View from triggering the callback again (useful if you want to ignore warnings of certain ViewControllers/Views).
     */
    public static func onDetect(debugDelay: TimeInterval = 0.1, releaseDelay: TimeInterval = 1.0, callback: @escaping (UIViewController?, UIView?, String)->Bool? ) {
        UIViewController.lvcdSwizzleLifecycleMethods()
        #if DEBUG
        self.delay = debugDelay
        #else
        self.delay = releaseDelay
        #endif
        self.callback = callback
    }
}

public extension UIView {
    
    /**
    Same as removeFromSuperview() but it also checks if it or any of its subviews don't deinit after the view is removed from the view tree. In that case the LeakedViewControllerDetector warning callback will be triggered.
     
    Before calling this make sure you have set LeakedViewControllerDetector.onDetect(){}, preferably in AppDelegate's application(_:didFinishLaunchingWithOptions:).
    
    Only use this method if the view is supposed to deinit shortly after it is removed from the view tree, or else it may trigger false warnings.
     */
    func removeFromSuperviewDetectLeaks() {
               
        removeFromSuperview()
        
        if LeakedViewControllerDetector.callback == nil {
            assertionFailure("Callback not set. Add LeakedViewControllerDetector.onDetect(){} to AppDelegate's application(_:didFinishLaunchingWithOptions:)")
        } else {
            UIViewController.checkForLeakedSubViewsIn(view: self, viewController: nil)
        }
    }
}

fileprivate extension UIViewController {
    
    static let lvcdCheckForMemoryLeakNotification = Notification.Name("lvcdCheckForMemoryLeak")
    static let lvcdCheckForSplitViewVCMemoryLeakNotification = Notification.Name("lvcdCheckForSplitViewVCMemoryLeak")
        
    static func lvcdSwizzleLifecycleMethods() {
        //this makes sure it can only swizzle once
        _ = self.lvcdActuallySwizzleLifecycleMethods
    }
       
    static let lvcdActuallySwizzleLifecycleMethods: Void = {
        let originalVdaMethod = class_getInstanceMethod(UIViewController.self, #selector(viewDidAppear(_:)))
        let swizzledVdaMethod = class_getInstanceMethod(UIViewController.self, #selector(lvcdViewDidAppear(_:)))
        method_exchangeImplementations(originalVdaMethod!, swizzledVdaMethod!)

        let originalVddMethod = class_getInstanceMethod(UIViewController.self, #selector(viewDidDisappear(_:)))
        let swizzledVddMethod = class_getInstanceMethod(UIViewController.self, #selector(lvcdViewDidDisappear(_:)))
        method_exchangeImplementations(originalVddMethod!, swizzledVddMethod!)
        
        let originalRfpMethod = class_getInstanceMethod(UIViewController.self, #selector(removeFromParent))
        let swizzledRfpMethod = class_getInstanceMethod(UIViewController.self, #selector(lvcdRemoveFromParent))
        method_exchangeImplementations(originalRfpMethod!, swizzledRfpMethod!)
        
        let originalSdvcMethod = class_getInstanceMethod(UISplitViewController.self, #selector(showDetailViewController(_:sender:)))
        let swizzledSdvcMethod = class_getInstanceMethod(UIViewController.self, #selector(lvcdShowDetailViewController(_:sender:)))
        method_exchangeImplementations(originalSdvcMethod!, swizzledSdvcMethod!)
    }()
    
    static let lvcdIgnoredViewControllers = ["_UIAlertControllerTextFieldViewController",
                                         "UIInputWindowController",
                                         "UICompatibilityInputViewController",
                                         "UISystemKeyboardDockController",
                                         "UISystemInputAssistantViewController",
                                         "UIPredictionViewController" ]
    
    func lvcdShouldIgnore() -> Bool {
        return Self.lvcdIgnoredViewControllers.contains(type(of: self).description())
        || self.view.layer.sublayers?.first(where: {$0 as? LVCDSplitViewLayer != nil}) != nil
    }
    
   
    @objc func lvcdViewDidAppear(_ animated: Bool) -> Void {
        lvcdViewDidAppear(animated) //run original implementation
        if !lvcdShouldIgnore() {
            NotificationCenter.default.removeObserver(self, name: Self.lvcdCheckForMemoryLeakNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(lvcdCheckForMemoryLeak), name: Self.lvcdCheckForMemoryLeakNotification, object: nil)
        }
    }

    @objc func lvcdViewDidDisappear(_ animated: Bool) -> Void {
        lvcdViewDidDisappear(animated) //run original implementation
        //ignore parent VCs because one of their children will trigger viewDidDisappear() too
        
        if !(self is UINavigationController || self is UITabBarController || self is UIPageViewController) && !lvcdShouldIgnore() {
            NotificationCenter.default.post(name: Self.lvcdCheckForMemoryLeakNotification, object: nil) //this will check every VC, just in case
        }
    }
    
    @objc func lvcdRemoveFromParent() -> Void {
        lvcdRemoveFromParent() //run original implementation
        if !lvcdShouldIgnore() {
            NotificationCenter.default.post(name: Self.lvcdCheckForMemoryLeakNotification, object: nil)
        }
    }
    
    @objc func lvcdShowDetailViewController(_ vc: UIViewController, sender: Any?) {
        NotificationCenter.default.post(name: Self.lvcdCheckForSplitViewVCMemoryLeakNotification, object: self)
        NotificationCenter.default.post(name: Self.lvcdCheckForMemoryLeakNotification, object: nil)
        if vc.view.layer.sublayers?.first(where: {$0 as? LVCDSplitViewLayer != nil}) == nil {
            let mldLayer = LVCDSplitViewLayer()
            mldLayer.splitViewController = self as? UISplitViewController
            mldLayer.viewController = vc
            vc.view.layer.addSublayer(mldLayer)
        }
       
        lvcdShowDetailViewController(vc, sender: sender) //run original implementation
    }
    
    static var lvcdMemoryCheckQueue = Set<ObjectIdentifier>()
    
    static func checkForLeakedSubViewsIn(view: UIView, viewController: UIViewController? = nil) {
        
        let delay = LeakedViewControllerDetector.delay
        let checkVC = viewController != nil
        
        view.iterateTopSubViews(viewController: viewController) { subview in
            let subview = subview //seems redundant but prevents error in older Swift versions
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak viewController, weak subview] in
                if (!checkVC || viewController == nil), let subview = subview, subview.rootView.layer.sublayers?.first(where: {$0 as? LVCDLayer != nil}) == nil {
                    let leakedView = subview.rootView
                    let errorTitle = "VIEW STILL IN MEMORY"
                    let errorMessage = leakedView.debugDescription

                    let showAlert = LeakedViewControllerDetector.callback?(nil, leakedView, "\(errorTitle) \(errorMessage)")
                    if showAlert ?? false {
                        Self.lvcdShowWarningAlert(errorTitle: errorTitle, errorMessage: errorMessage, objectIdentifier: Int.init(bitPattern: ObjectIdentifier.init(leakedView)))
                    }

                    if showAlert != nil {
                        let mldLayer = LVCDLayer()
                        mldLayer.memoryLeakDetectionDate = Date().timeIntervalSince1970 - delay
                        mldLayer.errorMessage = errorMessage
                        mldLayer.objectIdentifier = Int.init(bitPattern: ObjectIdentifier.init(leakedView))
                        mldLayer.objectType = "VIEW"
                        leakedView.layer.addSublayer(mldLayer)
                    }
                }
            }
        }
    }
    
    var lvcdRootParentViewController: UIViewController {
        parent?.lvcdRootParentViewController ?? self
    }

    @objc private func lvcdCheckForMemoryLeak() {
        let objectIdentifier = ObjectIdentifier.init(self)
        
        //in some cases lvcdCheckForMemoryLeakNotification may be called multiple times at once, this guard prevents double checking
        guard !Self.lvcdMemoryCheckQueue.contains(objectIdentifier) else { return }
        Self.lvcdMemoryCheckQueue.insert(objectIdentifier)
          
        DispatchQueue.main.async { [self] in
            Self.lvcdMemoryCheckQueue.remove(objectIdentifier)
            let rootParentVC = lvcdRootParentViewController
            guard rootParentVC.presentedViewController == nil,
                  (!self.isViewLoaded || rootParentVC.view.window == nil),
                  //once a leak was detected it adds a special layer to the root view to allow to detect if it deinits, if somehow already present no need to proceed
                  rootParentVC.view.layer.sublayers?.first(where: {$0 as? LVCDLayer != nil || $0 as? LVCDSplitViewLayer != nil}) == nil
            else { return }

            if let svc = self as? UISplitViewController {
                NotificationCenter.default.post(name: Self.lvcdCheckForSplitViewVCMemoryLeakNotification, object: svc)
            }

            Self.checkForLeakedSubViewsIn(view: view, viewController: self)
            
            let delay = LeakedViewControllerDetector.delay
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                
                //if self is nil it deinitted, so no memory leak
                guard let self = self else { return }
                
                //these conditions constitute a 'limbo' ViewController, i.e. a memory leak:
                if (!self.isViewLoaded || self.view.window == nil) && self.parent == nil && self.presentedViewController == nil {
                    
                    //once warned don't warn again
                    NotificationCenter.default.removeObserver(self, name: Self.lvcdCheckForMemoryLeakNotification, object: nil)
                   
                    let errorTitle = "VIEWCONTROLLER STILL IN MEMORY"
                    var errorMessage = self.debugDescription
                    
                    //add children's names to the message in case of NavVC or TabVC for easier identification
                    if let nvc = self as? UINavigationController {
                        errorMessage = "\(errorMessage):\n\(nvc.viewControllers)"
                    }
                    if let tbvc = self as? UITabBarController, let vcs = tbvc.viewControllers {
                        errorMessage = "\(errorMessage):\n\(vcs)"
                    }
                    
                    let showAlert = LeakedViewControllerDetector.callback?(self, nil, "\(errorTitle) \(errorMessage)")
                    
                    if showAlert ?? false {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            Self.lvcdShowWarningAlert(errorTitle: errorTitle, errorMessage: errorMessage, objectIdentifier: Int.init(bitPattern: ObjectIdentifier.init(self)))
                        }
                    }
                    
                    if showAlert != nil {
                        let mldLayer = LVCDLayer()
                        mldLayer.memoryLeakDetectionDate = Date().timeIntervalSince1970 - delay
                        mldLayer.errorMessage = errorMessage
                        mldLayer.objectIdentifier = Int.init(bitPattern: ObjectIdentifier.init(self))
                        mldLayer.objectType = "VIEWCONTROLLER"
                        self.view.layer.addSublayer(mldLayer)
                    }
                }
            }
        }
    }
    
    //call this if VC deinits, if memory leak was detected earlier it apparently resolved itself, so notify this:
    class func lvcdMemoryLeakResolved(memoryLeakDetectionDate: TimeInterval, errorMessage: String, objectIdentifier: Int, objectType: String) {

        let interval = Date().timeIntervalSince1970 - memoryLeakDetectionDate
        
        let errorTitle = "LEAKED \(objectType) DEINNITED"
        let errorMessage = String(format: "\(errorMessage)\n\nDeinnited after %.3fs.", interval)
                
        if LeakedViewControllerDetector.callback?(nil, nil, "\(errorTitle) \(errorMessage)") ?? false {
            Self.lvcdShowWarningAlert(errorTitle: errorTitle, errorMessage: errorMessage, objectIdentifier: objectIdentifier)
        }
    }
    
    static var lvcdAlertQueue = [UIAlertController]()
    
    class func lvcdShowWarningAlert(errorTitle: String?, errorMessage: String?, objectIdentifier: Int) {

        let alert = LVCDAlertController(title: errorTitle, message: errorMessage, preferredStyle: UIAlertController.Style.alert)
        alert.view.tag = objectIdentifier
        alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default) { action in
            if LeakedViewControllerDetector.warningWindow?.rootViewController?.presentedViewController == nil {
                LeakedViewControllerDetector.warningWindow = nil
            }
        })
        lvcdShowWarningAlert(alert)
    }
    
    class func lvcdShowWarningAlert(_ alert: UIAlertController?) {
        guard let alert = alert else { return }
        if let warningWindow = LeakedViewControllerDetector.warningWindow {
            
            if let tagAlertController = UIApplication.lvcdFindViewControllerWithTag(controller: warningWindow.rootViewController, tag: alert.view.tag) as? UIAlertController, !tagAlertController.isBeingDismissed {
                tagAlertController.title = alert.title
                tagAlertController.message = alert.message
            }
            else if let topViewController = UIApplication.lvcdTopViewController(controller: warningWindow.rootViewController) {
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
                if let windowScene = UIApplication.shared.lvcdFirstActiveWindowScene {
                    LeakedViewControllerDetector.warningWindow = UIWindow.init(windowScene: windowScene)
                } else {
                    assertionFailure("No WindowScene found to present warning alert dialog on.")
                }
            } else {
                LeakedViewControllerDetector.warningWindow = UIWindow.init(frame: UIScreen.main.bounds)
            }
            
            if let warningWindow = LeakedViewControllerDetector.warningWindow {
                warningWindow.rootViewController = LVCDViewController.init()
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
        override func viewDidAppear(_ animated: Bool) {
            //purposely not calling super here so it won't trigger a warning itself
        }
        override func viewDidDisappear(_ animated: Bool) {
            //purposely not calling super here so it won't trigger a warning itself
        }
    }
    
    class LVCDAlertController: UIAlertController {
        override func viewDidAppear(_ animated: Bool) {
            //purposely not calling super here so it won't trigger a warning itself
        }
        
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if LeakedViewControllerDetector.warningWindow?.rootViewController == self.presentingViewController {
                UIView.animate(withDuration: 0.25, delay: 0) {
                    LeakedViewControllerDetector.warningWindow?.alpha = 0.0
                }
            }
        }
        
        override func viewDidDisappear(_ animated: Bool) {
            //purposely not calling super here so it won't trigger a warning itself

            //failsafe in case somehow window doesn't go away you can at least see it
            DispatchQueue.main.async {
                LeakedViewControllerDetector.warningWindow?.alpha = 1.0
            }
        }
    }
    
    class LVCDSplitViewLayer: CALayer {
        weak var splitViewController: UISplitViewController?
        weak var viewController: UIViewController? { didSet {
            NotificationCenter.default.addObserver(self, selector: #selector(checkIfBelongsToSplitViewController(_:)), name: UIViewController.lvcdCheckForSplitViewVCMemoryLeakNotification, object: nil)
        }}
        
        @objc func checkIfBelongsToSplitViewController(_ notification: Notification ) {
            if notification.object as? UISplitViewController == splitViewController {
                self.removeFromSuperlayer()
                if !viewController!.lvcdShouldIgnore() {
                    NotificationCenter.default.removeObserver(viewController!, name: UIViewController.lvcdCheckForMemoryLeakNotification, object: nil)
                    NotificationCenter.default.addObserver(viewController!, selector: #selector(lvcdCheckForMemoryLeak), name: UIViewController.lvcdCheckForMemoryLeakNotification, object: nil)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + LeakedViewControllerDetector.delay) { [weak splitViewController, weak viewController] in
                    if splitViewController == nil {
                        viewController?.lvcdCheckForMemoryLeak()
                    }
                }
            }
        }
    }
}

fileprivate class LVCDLayer: CALayer {
    var memoryLeakDetectionDate: TimeInterval = 0.0
    var errorMessage = ""
    var objectIdentifier = 0
    var objectType = ""
    deinit {
        UIViewController.lvcdMemoryLeakResolved(memoryLeakDetectionDate: memoryLeakDetectionDate, errorMessage: errorMessage, objectIdentifier: objectIdentifier, objectType: objectType)
    }
}

fileprivate extension UIView {
    func iterateTopSubViews(viewController: UIViewController?, onViewFound: (UIView)->(Void)) {
        var hasSubview = false
        for subview in subviews {
            if viewController == nil || subview.viewController == viewController {
                subview.iterateTopSubViews(viewController: viewController, onViewFound: onViewFound)
                hasSubview = true
            }
        }
        if !hasSubview {
            onViewFound(self)
        }
    }
    
    var rootView: UIView {
        superview?.rootView ?? self
    }
}

fileprivate extension UIResponder {
    var viewController: UIViewController? {
        next as? UIViewController ?? next?.viewController
    }
}

fileprivate extension UIApplication {

    ///get a window, preferably once that is in foreground (active) in case you have multiple windows on iPad
    var lvcdActiveMainKeyWindow: UIWindow? {
        if #available(iOS 13, tvOS 13, *) {
            let activeScenes = connectedScenes.filter({$0.activationState == UIScene.ActivationState.foregroundActive})
            return (activeScenes.count > 0 ? activeScenes : connectedScenes)
                .flatMap {  ($0 as? UIWindowScene)?.windows ?? [] }
                .first { $0.isKeyWindow }
        } else {
            return keyWindow
        }
    }
    
    class func lvcdTopViewController(controller: UIViewController? = UIApplication.shared.lvcdActiveMainKeyWindow?.rootViewController) -> UIViewController? {
        return controller?.presentedViewController != nil ? lvcdTopViewController(controller: controller!.presentedViewController!) : controller
    }
    
    class func lvcdFindViewControllerWithTag(controller: UIViewController? = UIApplication.shared.lvcdActiveMainKeyWindow?.rootViewController, tag: Int) -> UIViewController? {
        return controller == nil ? nil : (controller!.view.tag == tag ? controller! : lvcdFindViewControllerWithTag(controller: controller!.presentedViewController, tag: tag))
    }
    
    @available(iOS 13.0, tvOS 13, *)
    var lvcdFirstActiveWindowScene: UIWindowScene? {
        let activeScenes = UIApplication.shared.connectedScenes.filter({$0.activationState == UIScene.ActivationState.foregroundActive && $0 is UIWindowScene})
        return (activeScenes.count > 0 ? activeScenes : UIApplication.shared.connectedScenes).first(where: {$0 is UIWindowScene}) as? UIWindowScene
    }
    
}
