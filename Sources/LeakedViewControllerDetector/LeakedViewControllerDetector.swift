//
//  LeakedViewControllerDetector.swift
//
//  Created by Jan de Vries on 16/04/2022.
//

import UIKit

/**
Automatically detects and warns you whenever a ViewController in your app closes but doesn't deinit.
 
Use LeakedViewControllerDetector.onDetect() to start detecting leaks.
*/

public class LeakedViewControllerDetector {
    
    fileprivate static var callback: ((UIViewController?, String)->Bool?)?
    fileprivate static var delay: Double = 1.0
    fileprivate static var warningWindow: UIWindow?

    /**
    Triggers the callback whenever a leaked ViewController is detected.
    
     - Parameter debugDelay: The time in seconds allowed for each ViewController to deinit itself after it has closed. If it is still in memory after the delay the callback will be triggered. It can be increased to prevent certain false positives. This value is only used for builds flagged with DEBUG, for release build the value of releaseDelay is used.
     - Parameter releaseDelay: Same as debugDelay but this value is used for release builds.
     - Parameter callback: This will be triggered every time a ViewController closes but doesn't deinit. It will trigger again once it does deinit (if ever). It provides the ViewController that has leaked and a warning message string that you can use to log. The provided ViewController will be nil in case it deinnited. Return true to show an alert dialog with the message. Return nil if you want to prevent a future deinit of the ViewController from triggering the callback again (useful if you want to ignore warnings of certain ViewControllers).
     */
    public static func onDetect(debugDelay: TimeInterval = 0.1, releaseDelay: TimeInterval = 1.0, callback: @escaping (UIViewController?, String)->Bool? ) {
        UIViewController.lvcdSwizzleLifecycleMethods()
        #if DEBUG
        self.delay = debugDelay
        #else
        self.delay = releaseDelay
        #endif
        self.callback = callback
    }
}

fileprivate extension UIViewController {
        
    static func lvcdSwizzleLifecycleMethods() {
        //this makes sure it can only swizzle once
        _ = self.lvcdActuallySwizzleLifecycleMethods
    }
       
    private static let lvcdActuallySwizzleLifecycleMethods: Void = {
        let originalVdaMethod = class_getInstanceMethod(UIViewController.self, #selector(viewDidAppear(_:)))
        let swizzledVdaMethod = class_getInstanceMethod(UIViewController.self, #selector(lvcdViewDidAppear(_:)))
        method_exchangeImplementations(originalVdaMethod!, swizzledVdaMethod!)

        let originalVddMethod = class_getInstanceMethod(UIViewController.self, #selector(viewDidDisappear(_:)))
        let swizzledVddMethod = class_getInstanceMethod(UIViewController.self, #selector(lvcdViewDidDisappear(_:)))
        method_exchangeImplementations(originalVddMethod!, swizzledVddMethod!)
        
        let originalRfpMethod = class_getInstanceMethod(UIViewController.self, #selector(removeFromParent))
        let swizzledRfpMethod = class_getInstanceMethod(UIViewController.self, #selector(lvcdRemoveFromParent))
        method_exchangeImplementations(originalRfpMethod!, swizzledRfpMethod!)
    }()
    
    func lvcdShouldIgnore() -> Bool {
        return ["UICompatibilityInputViewController", "_UIAlertControllerTextFieldViewController"].contains(type(of: self).description())
    }
    
    @objc func lvcdViewDidAppear(_ animated: Bool) -> Void {
        lvcdViewDidAppear(animated) //run original implementation
//        print("lvcdViewDidAppear \(self)")
        if !lvcdShouldIgnore() {
            NotificationCenter.default.removeObserver(self, name: Notification.Name.lvcdCheckForMemoryLeak, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(lvcdCheckForMemoryLeak), name: Notification.Name.lvcdCheckForMemoryLeak, object: nil)
        }
    }

    @objc func lvcdViewDidDisappear(_ animated: Bool) -> Void {
        lvcdViewDidDisappear(animated) //run original implementation
//        print("lvcdViewDidDisappear \(self)")
        //ignore parent VCs because one of their children will trigger viewDidDisappear() too
        if !(self is UINavigationController || self is UITabBarController) && !lvcdShouldIgnore() {
            NotificationCenter.default.post(name: Notification.Name.lvcdCheckForMemoryLeak, object: nil) //this will check every VC, just in case
        }
    }
    
    @objc func lvcdRemoveFromParent() -> Void {
        lvcdRemoveFromParent() //run original implementation
        NotificationCenter.default.post(name: Notification.Name.lvcdCheckForMemoryLeak, object: nil)
    }
    
    @objc private func lvcdCheckForMemoryLeak() {
//        print("lvcdCheckForMemoryLeak \(self)")
        let delay = LeakedViewControllerDetector.delay
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            
            //once a leak was detected it adds a special layer to the root view to allow to detect if it deinits, if somehow already present no need to proceed
            guard let self = self, self.view.layer.sublayers?.first(where: {$0 as? LVCDLayer != nil}) == nil else { return }
            
            //these conditions constitute a 'limbo' ViewController, i.e. a memory leak:
            if (!self.isViewLoaded || self.view.window == nil) && self.parent == nil && self.presentedViewController == nil {
                
                //once warned don't warn again
                NotificationCenter.default.removeObserver(self, name: Notification.Name.lvcdCheckForMemoryLeak, object: nil)
               
                let errorTitle = "VIEWCONTROLLER STILL IN MEMORY"
                var errorMessage = self.debugDescription
                
                //add children's names to the message in case of NavVC or TabVC for easier identification
                if let nvc = self as? UINavigationController {
                    errorMessage = "\(errorMessage):\n\(nvc.viewControllers)"
                }
                if let tbvc = self as? UITabBarController, let vcs = tbvc.viewControllers {
                    errorMessage = "\(errorMessage):\n\(vcs)"
                }
                
                let showAlert = LeakedViewControllerDetector.callback?(self, "\(errorTitle) \(errorMessage)")
                
                if showAlert ?? false {
//                    print("\(errorTitle) \(errorMessage)")
                    UIViewController.lvcdShowWarningAlert(errorTitle: errorTitle, errorMessage: errorMessage, objectIdentifier: Int.init(bitPattern: ObjectIdentifier.init(self)))
                }
                
                if showAlert != nil {
                    let mldLayer = LVCDLayer()
                    mldLayer.memoryLeakDetectionDate = Date().timeIntervalSince1970 - delay
                    mldLayer.errorMessage = errorMessage
                    mldLayer.objectIdentifier = Int.init(bitPattern: ObjectIdentifier.init(self))
                    self.view.layer.addSublayer(mldLayer)
                }
            }
        }
    }
    
    //call this if VC deinits, if memory leak was detected earlier it apparently resolved itself, so notify this:
    class func lvcdMemoryLeakResolved(memoryLeakDetectionDate: TimeInterval, errorMessage: String, objectIdentifier: Int) {

        let interval = Date().timeIntervalSince1970 - memoryLeakDetectionDate
        
        let errorTitle = "LEAKED VIEWCONTROLLER DEINNITED"
        let errorMessage = String(format: "\(errorMessage)\n\nDeinnited after %.3fs.", interval)
                
        if LeakedViewControllerDetector.callback?(nil, "\(errorTitle) \(errorMessage)") ?? false {
//            print("\(errorTitle) \(errorMessage)")
            UIViewController.lvcdShowWarningAlert(errorTitle: errorTitle, errorMessage: errorMessage, objectIdentifier: objectIdentifier)
        }
    }
    
    class func lvcdShowWarningAlert(errorTitle: String?, errorMessage: String?, objectIdentifier: Int) {

        let alert = LVCDAlertController(title: errorTitle, message: errorMessage, preferredStyle: UIAlertController.Style.alert)
        alert.view.tag = objectIdentifier
        alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default) { action in
            if LeakedViewControllerDetector.warningWindow?.rootViewController?.presentedViewController == nil {
                LeakedViewControllerDetector.warningWindow = nil
            }
        })

        if let warningWindow = LeakedViewControllerDetector.warningWindow {
            if let topViewController = UIApplication.lvcdTopViewController(controller: warningWindow.rootViewController) {
                if let alertController = topViewController as? LVCDAlertController, alertController.view.tag == objectIdentifier {
                    alertController.dismiss(animated: false) {
                        UIApplication.lvcdTopViewController(controller: warningWindow.rootViewController)?.present(alert, animated: true, completion: nil)
                    }
                } else {
                    topViewController.present(alert, animated: true)
                }
            } else {
                #if DEBUG
                fatalError("No ViewController found to present warning alert dialog on.")
                #endif
            }
        } else {

            if #available(iOS 13, tvOS 13, *) {
                if let windowScene = UIApplication.shared.lvcdGetFirstActiveWindowScene() {
                    LeakedViewControllerDetector.warningWindow = UIWindow.init(windowScene: windowScene)
                } else {
                    #if DEBUG
                    fatalError("No WindowScene found to present warning alert dialog on.")
                    #endif
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
                    warningWindow.backgroundColor = .systemPink.withAlphaComponent(0.25)
                }
                warningWindow.rootViewController?.present(alert, animated: true, completion: nil)
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
        
//        deinit {
//            print("\(self) deinit")
//        }
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
        
//        deinit {
//            print("\(self) deinit")
//        }
    }
    
    class LVCDLayer: CALayer {
        var memoryLeakDetectionDate:TimeInterval = 0.0
        var errorMessage: String = ""
        var objectIdentifier: Int = 0
        deinit {
            UIViewController.lvcdMemoryLeakResolved(memoryLeakDetectionDate: memoryLeakDetectionDate, errorMessage: errorMessage, objectIdentifier: objectIdentifier)
        }
    }
    
}

fileprivate extension UIApplication {

    class func lvcdTopViewController(controller: UIViewController? = UIApplication.shared.lvcdActiveMainKeyWindow?.rootViewController) -> UIViewController? {

        if let navigationController = controller as? UINavigationController {
            return lvcdTopViewController(controller: navigationController.visibleViewController)
        }
        if let tabController = controller as? UITabBarController {
            if let selected = tabController.selectedViewController {
                return lvcdTopViewController(controller: selected)
            }
        }
        if let presented = controller?.presentedViewController {
            return lvcdTopViewController(controller: presented)
        }
        if let pageVC = controller as? UIPageViewController {
            return pageVC.viewControllers?.first
        }
        return controller
    }

    ///get a window, preferably once that is in foreground (active) in case you have multiple windows on iPad
    var lvcdActiveMainKeyWindow: UIWindow? {
        get {
            if #available(iOS 13, tvOS 13, *) {
                let activeScenes = connectedScenes.filter({$0.activationState == UIScene.ActivationState.foregroundActive})
                return (activeScenes.count > 0 ? activeScenes : connectedScenes)
                    .flatMap {  ($0 as? UIWindowScene)?.windows ?? [] }
                    .first { $0.isKeyWindow }
            } else {
                return keyWindow
            }
        }
    }
    
    @available(iOS 13.0, tvOS 13, *)
    func lvcdGetFirstActiveWindowScene() -> UIWindowScene? {
        let activeScenes = UIApplication.shared.connectedScenes.filter({$0.activationState == UIScene.ActivationState.foregroundActive && $0 is UIWindowScene})
        return (activeScenes.count > 0 ? activeScenes : UIApplication.shared.connectedScenes).first(where: {$0 is UIWindowScene}) as? UIWindowScene
    }
}

fileprivate extension Notification.Name {
    static let lvcdCheckForMemoryLeak = Notification.Name("lvcdCheckForMemoryLeak")
}
