# LeakedViewControllerDetector for UIKit (iOS/tvOS)

[![UIKit only](https://img.shields.io/badge/UIKit-red)](https://swiftpackageindex.com/Janneman84/LeakedViewControllerDetector)
[![Platform compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FJanneman84%2FLeakedViewControllerDetector%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Janneman84/LeakedViewControllerDetector)
[![Catalyst compatible](https://img.shields.io/badge/iOSOnMac_|_Catalyst-critical)](https://swiftpackageindex.com/Janneman84/LeakedViewControllerDetector)
[![Swift compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FJanneman84%2FLeakedViewControllerDetector%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Janneman84/LeakedViewControllerDetector)
[![Swift Package Manager compatible](https://img.shields.io/badge/spm-compatible-brightgreen.svg?style=flat)](https://swift.org/package-manager)


### _Find leaked UIViews and UIViewControllers in real time in your UIKit app without even looking for them!_

Remember having to deal with weird issues in your iOS or tvOS app, that turned out to be caused by some memory leak? No more! LeakedViewControllerDetector helps you find leaked Views and ViewControllers in any UIKit app. Whenever a leak occurs you'll know about it rightaway! Best thing is that you hardly need to make any changes to your code: it's set and forget. It's a great help for every UIKit app!

## Features

- Detects whenever a UIView or UIViewController in your app closes but it (or any of its subviews) don't deinit
- Instantly shows a warning alert dialog as soon as a leak is detected (in debug builds)
- Works great in release builds too! You can log leak warnings to e.g. Crashlytics.
- Easy installation: set and forget
- Little to no changes to your code required
- Fast and efficient

_An alert with screenshot pops up when a leaked ViewController is detected. The alert updates if the leak resolves itself:_

<img width="650" alt="alert1" src="https://github.com/Janneman84/LeakedViewControllerDetector/assets/9085167/1ef5b541-df19-45b1-994f-6107ec72b8c0">
<!-- <img width="650" alt="alert1" src="https://github.com/Janneman84/LeakedViewControllerDetector/assets/9085167/fb2061d1-1f34-4b92-bb1c-d48dcc325dcc"> -->
<!-- <img width="650" alt="alert1" src="https://github.com/Janneman84/LeakedViewControllerDetector/assets/9085167/57af87d6-e858-4ae6-886e-4d6dd5bea530"> -->
<!-- <img width="650" alt="alert1" src="https://github.com/Janneman84/LeakedViewControllerDetector/assets/9085167/af81ecfc-e607-47cb-bad6-1a0a6e2ca46d"> -->
<!-- <img width="650" alt="alert1" src="https://github.com/Janneman84/LeakedViewControllerDetector/assets/9085167/debcefa5-6649-4d4d-8721-6aa42f640e86"> -->
<!-- <img width="700" alt="alert1" src="https://github.com/Janneman84/LeakedViewControllerDetector/assets/9085167/7e60ace6-3144-4830-ae38-408182cc5218"> -->

_The detector also detects leaked Views:_

<img width="271" alt="alert2" src="https://github.com/Janneman84/LeakedViewControllerDetector/assets/9085167/8a53c16b-fa7e-462b-a817-e949e8417882">

<br>
<br>

The alerts can be disabled so your users won't have to seen them.

<!--_An alert pops up when a leak is detected:_-->
<!---->
<!--<img width="280" alt="alert1" src="https://user-images.githubusercontent.com/9085167/170823721-b62c378d-ea68-40c2-9056-e651c5264141.jpg">-->
<!-- -->
<!--_The alert updates if the leak resolves itself:_-->
<!---->
<!--<img width="280" alt="alert2" src="https://user-images.githubusercontent.com/9085167/170823736-4485dc36-53b1-49b1-a917-ba711669de54.jpg">-->

## Quickstart
First install this package through SPM using the Github url `https://github.com/Janneman84/LeakedViewControllerDetector`. I suggest to use the main branch. Make sure the library is linked to the target: 

<img width="653" alt="librarylink" src="https://user-images.githubusercontent.com/9085167/170822025-40ab8fe1-36a3-4269-8de7-09f97655c183.png">

Or you can just copy/paste the `LeakedViewControllerDetector.swift` file to your project, which is not recommended since you won't receive updates this way.


Now if you used SPM add import to `AppDelegate`:
``` swift
import LeakedViewControllerDetector
```
Then add the following code to `application(_:didFinishLaunchingWithOptions:)` in the `AppDelegate` class:
``` swift
LeakedViewControllerDetector.onDetect() { leakedViewController, leakedView, message in
    #if DEBUG
    return true //show warning alert dialog
    #else
    //here you can log warning message to a server, e.g. Crashlytics
    return false //don't show warning to user
    #endif
}
```
As you can see the example uses different implementations for debug and release builds by checking the DEBUG flag. More details and examples are further below.

### Replace removeFromSuperview()

Most leak detection works without changing your code. However you do need to manually replace View's `removeFromSuperview()` with `removeFromSuperviewDetectLeaks()` everytime you want to remove a view and make sure it and all its subviews get deinnited:
``` swift
//once the view is removed it will warn you if it (or any of its subviews) haven't deinnited: 
someView.removeFromSuperviewDetectLeaks()
```
Of course only use this if the View is _supposed_ to deinit after it is removed, else you might end up with false warnings.

### Review your code
The rest of your code needs to comply to two trivial things. First, make sure that you always call `super` if you override `viewDidAppear()` and/or `viewDidDisappear()` in your ViewControllers. This is common practice so you probably already did this anyway, but it is essential that you do so now:

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

Second, if you want to remove items from a UIViewController array, like in UINavigationController, UITabBarController or UIPageViewController, don't use `remove(at:)` but use `removeFromparent()` instead:

``` swift
//navigationController?.viewControllers.remove(at:3)
navigationController?.viewControllers[3].removeFromParent()

//tabBarController?.viewControllers?.remove(at:3)
tabBarController?.viewControllers?[3].removeFromParent()
```

That's it! The leak detector is now fully operational. If your app is functioning correctly you won't notice anything. Now it's time to tweak the callback to your liking.


## Callback details
As you can see in the quickstart it is recommended to treat debug and release builds differently. If you're debugging it's nice to get a popup dialog warning you of an issue. But you don't want your users to see this, so you log instead. Let's walk through the arguments and return value of the callback.

``` swift
LeakedViewControllerDetector.onDetect(detectionDelay: 1.0) { leakedViewController, leakedView, message in
    return true
}
```
`detectionDelay` is the time in seconds a View or ViewController and its subviews get after it closes to deinit itself before it triggers a warning. If you get many deinit warnings you may want to increase this number. The default value of 1.0s should prevent most of them though. You may consider a tigther delay for debug builds.

The callback supplies the following:
- `leakedViewController`, note this is an optional. If a previously leaked VC deinits (resolves itself) this callback is triggered again but in that case both leakedViewController and leakedView will be nil.
- `leakedView`, same as leakedViewController but for Views.
- `message`, string that can be used to print to console or log to your server of choice

The callback expects an optional Bool to be returned:
- Return `true` to show an alert dialog with the warning message. Note: if you're using multiple windows on iPad the window that shows the alert isn't necessarily the window where the leak occurs.
- Return `false` to not show an alert dialog, this is recommended for release builds
- Return `nil` if you don't want the callback to trigger again if leakedViewController/leakedView deinits. This is typically used if you want to ignore warnings of certain classes or instances.

### Ignore example
If for some reason you want to ignore warnings of certain Views or ViewControllers, make sure you return `nil`:

``` swift
LeakedViewControllerDetector.onDetect() { leakedViewController, leakedView, message in
    //return nil to ignore:
    if let leakedViewController {
        if leakedViewController is IgnoreThisViewController {return nil}
        if type(of: leakedViewController).description() == "_IgnoreThisPrivateViewController" {return nil}
        if leakedViewController.view.tag == -1 {return nil}
    }
    if let leakedView {
        if leakedView is IgnoreThisView {return nil}
        if type(of: leakedView).description() == "_IgnoreThisPrivateView" {return nil}
        if leakedView.tag == -1 {return nil}
    }
    return true
}
```

The package already ignores a few ViewControllers by itself, you can find these in `LeakedViewControllerDetector.ignoredViewControllerClassNames`, `LeakedViewControllerDetector.ignoredViewClassNames` and `LeakedViewControllerDetector.ignoredWindowClassNames`. You can add and remove from these arrays as you see fit. This way you can prevent them from triggering a warning in the first place.

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

### Full example
When you tie everything together you'll end up with something like this:
```swift
#if DEBUG
let delay = 0.2
#else
let delay = 1.0
#endif
               
LeakedViewControllerDetector.onDetect(detectionDelay: delay) { leakedViewController, leakedView, message in
    //return nil to ignore warnings of certain Viewscontrollers/Views
    if let leakedViewController {
        // UIImagePickerController tends to leak for ~5 second when you close it
        if leakedViewController is UIImagePickerController {return nil}
        if leakedViewController is IgnoreThisViewController {return nil}
        if type(of: leakedViewController).description() == "_IgnoreThisPrivateViewController" {return nil}
        if leakedViewController.view.tag == -1 {return nil}
    }
    if let leakedView {
        if leakedView is IgnoreThisView {return nil}
        if type(of: leakedView).description() == "_IgnoreThisPrivateView" {return nil}
        if leakedView.tag == -1 {return nil}
    }

    #if DEBUG
    print(message)
    return true //show alert
    #else
    //log leak message to server:
    let error = NSError(domain: Bundle.main.bundleIdentifier ?? "bundleIdentifier",
                        code: 8,
                        userInfo: [NSLocalizedDescriptionKey: message])
    Crashlytics.crashlytics().record(error: error)
    return false //don't show alert
    #endif
}
```
Debug only example:
```swift
#if DEBUG
LeakedViewControllerDetector.onDetect() { leakedViewController, leakedView, message in
    //insert ignore code here
    print(message)
    return true //show alert
}
#endif
```
It's tempting to put the import line between DEBUG tags too. However you still need it if you're using `removeFromSuperviewDetectLeaks()` anywhere in your code. When the detection callback is not set calls to this method will just act as a regular `removeFromSuperview()`.

## How does this package detect leaked ViewControllers?
In essence all it really does is this:

``` swift
override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
           
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        
        //when self is nil the ViewController has deinnited, so no leak
        guard let self = self else { return }
        
        //if all these properties are nil the ViewController is considered to have leaked
        if self.view.window == nil && self.parent == nil && self.presentedViewController == nil && (view == nil || view.superview == nil) {
            print("Leaked ViewController detected: \(self)")
        }
    }
}
```
Of course there is a bit more to it than that to catch all the edge scenarios. Leaked Views are detected in a similar fashion. Feel free to look at the source code, it's pretty small. Unless you're doing fancy things this approach is surprisingly effective.

## Common causes of leaked Views/ViewControllers

Below is a list of common causes of memory leaks. You can use these to trigger a warning for testing purposes.

### 1. Referencing self in callbacks
Referencing `self` inside a callback is often the cause of a memory leak. This code will keep a ViewController, View, or any other object alive for 10 seconds: 

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
Make sure to always declare delegates as weak vars or else it's very likely to get a memory leak:
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
    //it's tempting to do this, but don't
    navigationController?.presentationController?.delegate = nil
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

### 7. Beware of SplitViewControllers
Using a SplitViewController on an iPhone does result in some perculiar behavior. If you push or present a detail VC from the master and then close it the VC will not be removed but will stay active in memory. If you push/present a new detail VC thén the previous VC will actually be removed. This package takes this behavior into account. Just keep in mind that if you close a detail VC it will very much stay alive until you open a new one. It's not strictly a memory leak but it is a common cause of related issues if you're not aware of this behavior. Also fun is that on iPhone the initial detail VC _never_ deinits, so yeah...

### 8. ScrollView inertia
If you have e.g. a long TableView and you swipe down it will keep scrolling for a little while before it stops. Now if you close the VC while this is happening the TableView will stay in memory for up to a second. This applies to all forms of ScrollViews. There does not seem to be a way to prevent this. The package is designed to wait at least a second before checking for leaks in this specific case to prevent false positives.

### 9. UITextView URL preview
iOS is not without its flaws, I noticed it has some memory leaks of its own. One that keeps bugging me is UITextViews. If you turn off editable, turn on isSelectable, enable link detection and add a URL to the text you get a nice preview if you long press the URL. However once you have done this the UITextView will be stuck in memory forever! I don't know how to fix this. In iOS 17 this can be fixed by subclassing the TextView and overriding `removeFromSuperview()`:

```swift
//in UITextView subclass
override func removeFromSuperview() {
    let wasSelectable = isSelectable
    isSelectable = false
    super.removeFromSuperview()
    isSelectable = wasSelectable
}
```
### 10. UITextField in iOS 17
Text fields seem to have issues deinitting in iOS 17, mainly if `textContentType` is set. If you have a VC with multiple text fields, use at least one of them, then close the VC. Then ALL its text fields will leak until you use a different text field. I currently don't know how to deal with this.

### Tips are welcome

Do you know other causes of leaks that aren't listed here? Please let me know in the Issues section so I can add them.

## How do I know what causes my View or ViewController to leak?
This package only knows if a leak occurs but it doesn't know _why_: that's up to you to figure out. The list above should help you find the culprit. If you also get a deinit warning this probably means it has to do with a network call or some animation. In some cases you may get warnings of both ViewControllers and Views. Concentrate on fixing the ViewController first then any View warnings will usually go away too. A good strategy is to keep undressing your View or ViewController (mainly `ViewDidLoad()`) until the leak stops occuring. Or completely undress it first then put everything back piece by piece, or something in the middle (binary search).    

## Using deinit{}
You can add `deinit{}` to any object to monitor if it deinits. A typical usage is `deinit{print("deinit \(self)")}`. Watch your console and see if the print shows up when the object is supposed to deinit. If you get a memory leak warning you may want to add this to the class to confirm that it actually leaked and/or a fix worked. 

## Why not just use Instruments?
You can use Xcode's instruments to find memory leaks. However these can be complicated to use and only works if you are specifically searching for leaks. The advantage of this package is that it always works and you don't have to keep it in mind. Also it works when your users are using it so you know when a memory leak occurs in the wild. Note that this package only detects leaked ViewControllers and its Views and not other objects like the instruments can. ViewControllers tend to be the culprit of most leaks though so it's a good start.

## Performance
Performance shouldn't be an issue for most apps because the code is well optimized. If you're concerned you may choose to just check for leaks in debug builds. If you're experiencing performance issues or any other issues make sure to let me know in the Issues section.

## SwiftUI
This package is not designed or tested to be used with SwiftUI. Since SwiftUI is much more struct based memory leaks aren't as much a thing there anyway. 

## Why wasn't this package created 10 years ago?
I wish it was, would have saved me lots of headaches... Now UIKit is gradually being replaced with SwiftUI making this package obsolete ;). Technically it doesn't do anything that wasn't possible 10 years ago, so it's a bit late to the party I know. Better late than never!

## Disclaimer
This package may produce false or positives or false negatives in certain situations. It is not guaranteed to catch every memory leak and it only detects leaked ViewControllers and its Views, not other object. Please go to the Issues section if you're experiencing trouble. This package makes use of method swizzling of the following methods: UIViewController's `viewDidAppear()`, `viewDidDisappear()`, `removeFromParent()` and UISplitViewController's `showDetailViewController()`.

## License

MIT

## Testimonials
Has this package helped you find any leaks? Please leave a message in the testimonials thread in the Issues section!

