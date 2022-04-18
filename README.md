# LeakedViewControllerDetector

### _Find leaked ViewControllers without even looking for them!_

LeakedViewControllerDetector helps you find leaked ViewControllers in your iOS UIKit app. It's easy to accidentally create a retain cycle causing a ViewController to stay in memory, causing weird issues in your app. This package warns you as soon as this occurs, helping you to track down the cause of the leak and improve the stability of your app.

## Features

- Warns you instantly whenever a ViewController closes but doesn't deinit
- Shows alert dialog (debug) or logs warning to e.g. Crashlytics (release), so you know where and when a leak occurs
- Easy installation
- Little to no changes to your code required

## Quickstart
First install this package through SPM using the Github url, then add the following code to `didFinishLaunchingWithOptions` in `AppDelegate`:
```
#if DEBUG
MemoryLeakDetector.shared.onLeakedViewControllerDetected(delay: 1/60.0) { leakedViewController, message in
    return true //show warning alert dialog
}
#else
MemoryLeakDetector.shared.onLeakedViewControllerDetected(delay: 1.0) { leakedViewController, message in
    //log warning message to a server, e.g. Crashlytics
    return false //don't show warning to user
}
#endif
```
As you can see it uses different implementations for debug and release builds. More details and examples are further below.

### Review your code
First, make sure that you always call `super` if you override `viewDidLoad()` and/or `viewDidDisappear()` in your ViewControllers. This is common practice so you probably already did this anyway, but is essential that you do now.

```
override func viewDidLoad() {
    super.viewDidLoad() //don't forget this!
    ...
}

override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated) //don't forget this!
    ...
}
```

Second, if you want to remove items from a UIViewController array, like in UINavigationController or UITabBarController, don't use `remove(at:)` but use `removeFromparent()` instead:

```
//navigationController?.viewControllers.remove(at:3)
navigationController?.viewControllers[3].removeFromParent()

//tabBarController?.viewControllers?.remove(at:3)
tabBarController?.viewControllers?[3].removeFromParent()
```

That's it! The leak detector is now fully operational. If your app is functioning correctly you won't notice anything. Further below is a list of common causes of memory leaks. You can use these to trigger a warning.


## Callback details
As you can see in the quickstart it is recommended to treat debug and release builds differently. If you're debugging it's nice to get a popup dialog warning you of an issue, but you don't want your users to see this, so you log instead. Let's walk through the arguments of the callback.

```
MemoryLeakDetector.shared.onLeakedViewControllerDetected(delay: 1/60.0) { leakedViewController, message in
    return true
}
```
Delay is the time the ViewController gets after it closes to deinit itself before it triggers a warning. If you get false positives you may want to increase this number. I recommend a tighter value for debug builds and 1 second for release builds.

The callback supplies the following:
- leakedViewController, note this is an optional. If a previously leaked VC deinits (resolves itself) this callback is triggered again but in that case leakedViewController will be nil.
- message, can be used to print to console or log to your server of choice

The callback expects an optional Bool to be returned:
- Return true to show an alert dialog with the warning message. Note: if you're using multiple windows on iPad the window that shows the alert isn't necessarily the window where the leak occurs.
- Return false to not show an alert dialog, this is recommended for release builds
- Return nil if you don't want the callback to trigger again if leakedViewController deinits. This is typically used if you want to ignore warnings of certain classes or instances.

### Ignore example
If for some reason you want to ignore warnings of certain ViewControllers, make sure you return nil:

```
MemoryLeakDetector.shared.onLeakedViewControllerDetected(delay: 1/60.0) { leakedViewController, message in
    //return nil to ignore:
    if leakedViewController is IgnoreThisViewController {
        return nil
    }
    if leakedViewController.view.tag == -1 {
        return nil
    }
    return true
}
```

### Crashlytics example
If you're using Crashlytics you can log the warning message like so:

```
import FirebaseCrashlytics
```

```
let error = NSError(domain: Bundle.main.bundleIdentifier!,
                      code: 8, //whatever number you fancy
                  userInfo: [NSLocalizedDescriptionKey: message])
Crashlytics.crashlytics().record(error: error)
```

## How does this package detect leaked ViewControllers?
In essence all it really does is this:

```
override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
           
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        
        //when self is nil the ViewController has deinnited, so no leak
        guard let self = self else { return }
        
        //if all these properties are nil the ViewController is considered to have leaked
        if self.view.window == nil && self.parent == nil && self.presentedViewController == nil {
            print("Leaked ViewController detected: \(self)")
        }
    }
}
```
Of course there is a bit more to it than that to catch all the edge scenarios. Feel free to look at the source code, it's pretty small. Unless you're doing fancy things this approach is surprisingly effective.

## Common causes of leaked ViewControllers
### 1. Referencing self in callbacks
Referencing `self` inside a callback is often the cause of a memory leak. This code will keep a ViewController (or any other object) alive for 10 seconds: 

```
DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
    print(self)
}
```

This will trigger a memory leak warning if you close the ViewController before the 10 seconds are over. After the 10 seconds you will see another warning telling you the ViewController has deinnited itself. This scenario is also typical for a slow network request that eventually finishes or times out.

These issues are easily fixed by using `[weak self]`, as you probably know:
```
DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
    guard let self = self else {return}
    print(self)
}
```

### 2. NotificationCenter observer callback

Don't forget to also use `[weak self]` when observing for notifications like this, or else the ViewController will stay in memory forever:

```
NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "SomeNotification"), object: nil, queue: nil) { [weak self] notification in
    print(self)
}
```

Or instead you can observe using a selector like this, which cannot cause a memory leak:
```
NotificationCenter.default.addObserver(self, selector: #selector(someMethod), name: Notification.Name("SomeNotification"), object: nil)
```

### 3. Using non-weak delegates
Make sure to always declare delegates as weak vars or else you will get a memory leak:
```
weak var delegate: MyViewControllerDelegate?
```

### 4. ViewController PresentationController Delegate
Sometimes you want to set the PresentationController delegate, for example if you want to implement `presentationControllerShouldDismiss()`. However if you set this delegate if your ViewController is a child of a parent like a NavigationController it won't trigger the delegate methods but will cause a permanent memory leak instead:
```
self.presentationController?.delegate = self
```

Instead it's best to just always use this:
```
self.presentingViewController?.presentedViewController?.presentationController?.delegate = self
```
This trick makes sure the delegate is always set to the parent, whatever it is.

### 5. NavigationController PresentationController delegate
This is a sneaky one. If your ViewController is inside a NavigationController and you set its presentationController delegate right after it closed it will keep itself and its children in memory forever:
```
override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    navigationController?.presentationController?.delegate = self //or nil, doesn't matter
}
```
So present a NavigationController with a ViewController with this code. Then close the NavigationController and you'll see a memory warning.

### Tips are welcome


Do you know other causes of leaks that aren't listed here? Please let me know in the Issues section so I can add them.

## Disclaimer
This package may produce false or positives or false negatives in certain situations. It is not guaranteed to catch every memory leak. Please go to the Issues section if you're experiencing trouble. This package makes use of method swizzling of the following methods of `UIViewController`: `viewDidLoad()`, `viewDidDisappear()` and `removeFromParent()`.


## License

MIT
