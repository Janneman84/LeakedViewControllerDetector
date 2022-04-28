# LeakedViewControllerDetector
[![Swift Package Manager compatible](https://img.shields.io/badge/spm-compatible-brightgreen.svg?style=flat)](https://swift.org/package-manager)

### _Find leaked ViewControllers without even looking for them!_

LeakedViewControllerDetector helps you find leaked ViewControllers in your iOS UIKit app. It's easy to accidentally create a retain cycle causing a ViewController to stay in memory. These memory leaks often cause weird issues in your app. This package warns you as soon as this occurs, helping you to track down the cause of the memory leak and improve the stability of your app. 
## Features

- Warns you instantly whenever a ViewController in your app closes but doesn't deinit
- Shows alert dialog (debug) or you can log a warning to e.g. Crashlytics (release) when this happens
- Easy installation: set and forget
- Little to no changes to your code required

_An alert pops up when a leak is detected:_

![lvcd_alert1](https://user-images.githubusercontent.com/9085167/163881885-1e087286-3f91-41b9-8a76-0bfab7815840.jpg)
 
_Another alert pops up if the leak resolves itself:_

![lvcd_alert2](https://user-images.githubusercontent.com/9085167/163881927-740cb4f8-9541-4b32-a0dc-6ab421f4fb79.jpg)

## Quickstart
First install this package through SPM using the Github url `https://github.com/Janneman84/LeakedViewControllerDetector`. I suggest to use the main branch. Make sure the library is linked to the target: 

![lvcd_librarylink](https://user-images.githubusercontent.com/9085167/163882303-63abc092-fff0-46dd-9d0d-4f22a18cf7ae.png)

Or you can just copy/paste the LeakedViewControllerDetector.swift file to your project, which is not recommended since you won't receive updates this way.


Next add import to `AppDelegate`:
``` swift
import LeakedViewControllerDetector
```
Then add the following code to `application(_:didFinishLaunchingWithOptions:)` in the `AppDelegate` class:
``` swift
LeakedViewControllerDetector.onDetect() { leakedViewController, message in
    #if DEBUG
    return true //show warning alert dialog
    #else
    //log warning message to a server, e.g. Crashlytics
    return false //don't show warning to user
    #endif
}
```
As you can see the example uses different implementations for debug and release builds by checking the DEBUG flag. More details and examples are further below.

### Review your code
First, make sure that you always call `super` if you override `viewDidAppear()` and/or `viewDidDisappear()` in your ViewControllers. This is common practice so you probably already did this anyway, but it is essential that you do now.

``` swift
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated) //don't forget this!
    ...
}

override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated) //don't forget this!
    ...
}
```

Second, if you want to remove items from a UIViewController array, like in UINavigationController or UITabBarController, don't use `remove(at:)` but use `removeFromparent()` instead:

``` swift
//navigationController?.viewControllers.remove(at:3)
navigationController?.viewControllers[3].removeFromParent()

//tabBarController?.viewControllers?.remove(at:3)
tabBarController?.viewControllers?[3].removeFromParent()
```

That's it! The leak detector is now fully operational. If your app is functioning correctly you won't notice anything. Further below is a list of common causes of memory leaks. You can use these to trigger a warning.


## Callback details
As you can see in the quickstart it is recommended to treat debug and release builds differently. If you're debugging it's nice to get a popup dialog warning you of an issue, but you don't want your users to see this, so you log instead. Let's walk through the arguments of the callback.

``` swift
LeakedViewControllerDetector.onDetect(debugDelay: 0.1, releaseDelay: 1.0) { leakedViewController, message in
    return true
}
```
`debugDelay` and `releaseDelay` is the time in seconds the ViewController gets after it closes to deinit itself before it triggers a warning (for debug and release build respectively). If you get false positives you may want to increase this number. I recommend a tighter value like 0.1s for debug builds and 1.0s for release builds (which are the default values).

The callback supplies the following:
- `leakedViewController`, note this is an optional. If a previously leaked VC deinits (resolves itself) this callback is triggered again but in that case leakedViewController will be nil.
- `message`, can be used to print to console or log to your server of choice

The callback expects an optional Bool to be returned:
- Return `true` to show an alert dialog with the warning message. Note: if you're using multiple windows on iPad the window that shows the alert isn't necessarily the window where the leak occurs.
- Return `false` to not show an alert dialog, this is recommended for release builds
- Return `nil` if you don't want the callback to trigger again if leakedViewController deinits. This is typically used if you want to ignore warnings of certain classes or instances.

### Ignore example
If for some reason you want to ignore warnings of certain ViewControllers, make sure you return `nil`:

``` swift
LeakedViewControllerDetector.onDetect() { leakedViewController, message in
    //return nil to ignore:
    if leakedViewController is IgnoreThisViewController {
        return nil
    }
    if type(of: leakedViewController).description() == "_IgnoreThisPrivateViewController" {
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

``` swift
import FirebaseCrashlytics
```

``` swift
let error = NSError(domain: Bundle.main.bundleIdentifier!,
                      code: 8, //whatever number you fancy
                  userInfo: [NSLocalizedDescriptionKey: message])
Crashlytics.crashlytics().record(error: error)
```

## How does this package detect leaked ViewControllers?
In essence all it really does is this:

``` swift
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

``` swift
DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
    print(self)
}
```

This will trigger a memory leak warning if you close the ViewController before the 10 seconds are over. After the 10 seconds you will see another warning telling you the ViewController has deinnited itself. This scenario is also typical for a slow network request that eventually finishes or times out.

These issues are easily fixed by using `[weak self]`, as you probably know:
``` swift
DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
    guard let self = self else {return}
    print(self)
}
```

### 2. NotificationCenter observer callback

Don't forget to also use `[weak self]` when observing for notifications like this, or else the ViewController will stay in memory forever:

``` swift
NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "SomeNotification"), object: nil, queue: nil) { [weak self] notification in
    print(self)
}
```

Or instead you can observe using a selector like this, which cannot cause a memory leak:
``` swift
NotificationCenter.default.addObserver(self, selector: #selector(someMethod), name: Notification.Name("SomeNotification"), object: nil)
```

### 3. Using non-weak delegates
Make sure to always declare delegates as weak vars or else you will get a memory leak:
``` swift
weak var delegate: MyViewControllerDelegate?
```

### 4. ViewController PresentationController Delegate
Sometimes you want to set the PresentationController delegate, for example if you want to implement `presentationControllerShouldDismiss()`. However if you set this delegate if your ViewController is a child of a parent like a NavigationController it won't trigger the delegate methods but will cause a permanent memory leak instead:
``` swift
self.presentationController?.delegate = self
```

Instead it's best to just always use this:
``` swift
self.presentingViewController?.presentedViewController?.presentationController?.delegate = self
```
This trick makes sure the delegate is always set to the parent, whatever it is.

### 5. NavigationController PresentationController delegate
This is a sneaky one. If your ViewController is inside a NavigationController and you set its presentationController delegate right after it closed it will keep itself and its children in memory forever:
``` swift
override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    navigationController?.presentationController?.delegate = self //or nil, doesn't matter
}
```
So present a NavigationController with a ViewController with this code. Then close the NavigationController and you'll see a memory warning.

### 6. UIAlertController action callback
Sometimes you want to reference an alert inside one of its actions' callback. In that case make sure you use `unowned` or `weak` or the alert will linger in memory forever. You can use `unowned` if you're certain it won't be nil (which is the case here), it's basically the same as explicitly unwrapping `weak`:
``` swift
//since we're referencing alert inside the callbacks use unowned or weak or it will never deinit
let alert = UIAlertController.init(title: "Retain test", message: nil, preferredStyle: .alert)
alert.addAction(UIAlertAction.init(title: "Unowned", style: .default) { [unowned alert] action in
    print(alert)
})
alert.addAction(UIAlertAction.init(title: "Weak", style: .default) { [weak alert] action in
    print(alert!) //explicitly unwrapping weak alert works basically the same as using unowned
})
self.present(alert, animated: true)
```

### 6. Hitting breakpoints or using Debug View Hierarchy
There are some cases where hitting a breakpoint and/or using the view hierarchy debugger in an app may lead to (what appears to be) memory leaks and other weird issues. I don't have any reproducable steps yet but if I do I will list them here. Please let me know in the Issues section if you know more about this.

### Tips are welcome

Do you know other causes of leaks that aren't listed here? Please let me know in the Issues section so I can add them.

## How do I know what causes my ViewController to leak?
This package only knows if a leak occurs but it doesn't know _why_: that's up to you to figure out. The list above should help you find the culprit. If you also get a deinit warning this probably means it has to do with a network call or some animation. A good strategy is to keep undressing your ViewController (mainly `ViewDidLoad()`) until the leak stops occuring. Or completely undress it first then put everything back piece by piece, or something in the middle (binary search).    

## Why not just use Instruments?
You can use Xcode's instruments to find memory leaks. However these can be complicated to use and only works if you are specifically searching for leaks. The advantage of this package is that it always works and you don't have to mind it. Also it works when your users are using it so you know when a memory leak occurs in the wild. Note that this package only detects leaked ViewControllers and not other objects like the instruments can. ViewControllers tend to be the culprit of most leaks though so it's a good start.

## Disclaimer
This package may produce false or positives or false negatives in certain situations. It is not guaranteed to catch every memory leak and it only detects leaked ViewControllers, not other object. Please go to the Issues section if you're experiencing trouble. This package makes use of method swizzling of the following methods of `UIViewController`: `viewDidAppear()`, `viewDidDisappear()` and `removeFromParent()`.


## License

MIT
