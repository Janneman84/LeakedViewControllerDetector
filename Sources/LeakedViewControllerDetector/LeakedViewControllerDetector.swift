//
//  LeakedViewControllerDetector.swift
//
//  Created by Jan de Vries on 16/04/2022.
//

import UIKit

/**
Singleton class that detects and warns you when any ViewController in your app closes but doesn't deinit.
 
Use LeakedViewControllerDetector.shared.onLeakedViewControllerDetected() to start detecting leaks.
*/

public class LeakedViewControllerDetector {
    
    public static let shared = LeakedViewControllerDetector()

    private init() {
        UIViewController.swizzleLifecycleMethods()
    }

    fileprivate var callback: ((UIViewController?, String)->Bool?)?
    fileprivate var delay: Double = 1.0
    fileprivate var includeApplicationStates = false
    
    /**
    Make sure to call this on shared and not on LeakedViewControllerDetector directly.
    
     - Parameter delay: The time in seconds allowed for each ViewController to deinit itself after it has closed. If it is still in memory after the delay the callback will be triggered. It can be increased to prevent certain false positives.
     - Parameter showStates: Set to true to include the application state (active, inactive, background) of when a leak was detected/resolved to the message string. Useful if you suspect a leak only occurs when in the background for example.
     - Parameter callback: This will be triggered every time a ViewController closes but doesn't deinit. It will trigger again once it does deinit (if ever). It provides the ViewController that has leaked and a warning message string that you can use to log. The provided ViewController will be nil in case it deinnited. Return true to show an alert dialog with the message. Return nil if you want to prevent a future deinit of the ViewController from triggering the callback again (useful if you want to ignore warnings of certain ViewControllers).
     */
    public func onLeakedViewControllerDetected(delay: TimeInterval = 1.0, showStates: Bool = false, callback: @escaping (UIViewController?, String)->Bool? ) {
        self.delay = delay
        self.includeApplicationStates = showStates
        self.callback = callback
    }
}

fileprivate extension UIViewController {
        
    static func swizzleLifecycleMethods() {
        //this makes sure it can only swizzle once
        _ = self.actuallySwizzleLifecycleMethods
    }
       
    private static let actuallySwizzleLifecycleMethods: Void = {
        let originalVdaMethod = class_getInstanceMethod(UIViewController.self, #selector(viewDidDisappear(_:)))
        let swizzledVdaMethod = class_getInstanceMethod(UIViewController.self, #selector(lvcdViewDidDisappear(_:)))
        method_exchangeImplementations(originalVdaMethod!, swizzledVdaMethod!)
        
        let originalVdlMethod = class_getInstanceMethod(UIViewController.self, #selector(viewDidLoad))
        let swizzledVdlMethod = class_getInstanceMethod(UIViewController.self, #selector(lvcdViewDidLoad))
        method_exchangeImplementations(originalVdlMethod!, swizzledVdlMethod!)

        let originalRfpMethod = class_getInstanceMethod(UIViewController.self, #selector(removeFromParent))
        let swizzledRfpMethod = class_getInstanceMethod(UIViewController.self, #selector(lvcdRemoveFromParent))
        method_exchangeImplementations(originalRfpMethod!, swizzledRfpMethod!)
    }()
    
    func shouldIgnore() -> Bool {
        return ["UICompatibilityInputViewController", "_UIAlertControllerTextFieldViewController"].contains(type(of: self).description())
    }
    
    @objc func lvcdViewDidLoad() -> Void {
        lvcdViewDidLoad() //run original implementation
        if !shouldIgnore() {
            NotificationCenter.default.addObserver(self, selector: #selector(checkForMemoryLeak), name: Notification.Name.lvcdCheckForMemoryLeak, object: nil)
        }
    }

    @objc func lvcdViewDidDisappear(_ animated: Bool) -> Void {
        lvcdViewDidDisappear(animated) //run original implementation
        
        //ignore parent VCs because one of their children will trigger viewDidDisappear() too
        if !(self is UINavigationController || self is UITabBarController) && !shouldIgnore() {
            NotificationCenter.default.post(name: Notification.Name.lvcdCheckForMemoryLeak, object: nil) //this will check every VC, just in case
        }
    }
    
    @objc func lvcdRemoveFromParent() -> Void {
        lvcdRemoveFromParent() //run original implementation
        NotificationCenter.default.post(name: Notification.Name.lvcdCheckForMemoryLeak, object: nil)
    }
    
    @objc private func checkForMemoryLeak() {
        
        let delay = LeakedViewControllerDetector.shared.delay
        
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
                
                if LeakedViewControllerDetector.shared.includeApplicationStates {
                    switch UIApplication.shared.applicationState {
                    case .active:
                        errorMessage = "\(errorMessage)\napp state on leak: ACTIVE"
                    case .inactive:
                        errorMessage = "\(errorMessage)\napp state on leak: INACTIVE"
                    case .background:
                        errorMessage = "\(errorMessage)\napp state on leak: BACKGROUND"
                    @unknown default:
                        errorMessage = "\(errorMessage)\napp state on leak: UNKNOWN STATE"
                    }
                }
                
                let showDialog = LeakedViewControllerDetector.shared.callback?(self, "\(errorTitle) \(errorMessage)")
                
                if showDialog ?? false {
//                    print("\(errorTitle) \(errorMessage)")
                    let alert = LVCDAlertController(title: errorTitle, message: errorMessage, preferredStyle: UIAlertController.Style.alert)
                    alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default))
                    alert.view.tag = Int.init(bitPattern: ObjectIdentifier.init(self)) //- UIApplication.shared.applicationState.rawValue
                    UIApplication.lvcdTopViewController()?.present(alert, animated: true, completion: nil)
                }
                
                if showDialog != nil {
                    let mldLayer = LVCDLayer()
                    mldLayer.memoryLeakDetectionDate = Date().timeIntervalSince1970 - delay
                    mldLayer.errorMessage = errorMessage
                    mldLayer.objectIdentifier = Int.init(bitPattern: ObjectIdentifier.init(self)) //- UIApplication.shared.applicationState.rawValue
                    self.view.layer.addSublayer(mldLayer)
                }
            }
        }
    }
    
    class LVCDAlertController: UIAlertController {
        override func viewDidLoad() {
            //purposely not calling super here so it won't trigger a warning itself
        }
        
        override func viewDidDisappear(_ animated: Bool) {
            //purposely not calling super here so it won't trigger a warning itself
        }
    }
    
    //call this if VC deinits, if memory leak was detected earlier it apparently resolved itself, so notify this:
    class func memoryLeakResolved(memoryLeakDetectionDate: TimeInterval, errorMessage: String, objectIdentifier: Int) {

        let interval = Date().timeIntervalSince1970 - memoryLeakDetectionDate
        
        let errorTitle = "LEAKED VIEWCONTROLLER DEINNITED"
        var errorMessage = errorMessage
        
        if LeakedViewControllerDetector.shared.includeApplicationStates {
            switch UIApplication.shared.applicationState {
            case .active:
                errorMessage = "\(errorMessage)\napp state on deinit: ACTIVE"
            case .inactive:
                errorMessage = "\(errorMessage)\napp state on deinit: INACTIVE"
            case .background:
                errorMessage = "\(errorMessage)\napp state on deinit: BACKGROUND"
            @unknown default:
                errorMessage = "\(errorMessage)\napp state on deinit: UNKNOWN STATE"
            }
        }
        
        errorMessage = String(format: "\(errorMessage)\n\nDeinnited after %.3fs.", interval)
        
        if LeakedViewControllerDetector.shared.callback?(nil, "\(errorTitle) \(errorMessage)") ?? false {
            print("\(errorTitle) \(errorMessage)")
            let alert = LVCDAlertController(title: errorTitle, message: errorMessage, preferredStyle: UIAlertController.Style.alert)
            alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default))

            //dismiss previous warning dialog about the same VC first if still present
            if let topViewController = UIApplication.lvcdTopViewController() {
                if let alertController = topViewController as? LVCDAlertController, alertController.view.tag == objectIdentifier {
                    alertController.dismiss(animated: false) {
                        UIApplication.lvcdTopViewController()?.present(alert, animated: true)
                    }
                } else {
                    topViewController.present(alert, animated: true)
                }
            }
        } else {
            #if DEBUG
            fatalError("No ViewController found to present warning alert dialog on.")
            #endif
        }
    }
}

fileprivate class LVCDLayer: CALayer {
    var memoryLeakDetectionDate:TimeInterval = 0.0
    var errorMessage: String = ""
    var objectIdentifier: Int = 0
    deinit {
        UIViewController.memoryLeakResolved(memoryLeakDetectionDate: memoryLeakDetectionDate, errorMessage: errorMessage, objectIdentifier: objectIdentifier)
    }
}

fileprivate extension Notification.Name {
    static let lvcdCheckForMemoryLeak = Notification.Name("lvcdCheckForMemoryLeak")
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
}

fileprivate extension UIApplication {
    ///get a window, preferably once that is in foreground (active) in case you have multiple windows on iPad
    var lvcdActiveMainKeyWindow: UIWindow? {
        get {
            if #available(iOS 13, *) {
                let activeScenes = connectedScenes.filter({$0.activationState == UIScene.ActivationState.foregroundActive})
                return (activeScenes.count > 0 ? activeScenes : connectedScenes)
                    .flatMap {  ($0 as? UIWindowScene)?.windows ?? [] }
                    .first { $0.isKeyWindow }
            } else {
                return keyWindow
            }
        }
    }
}
