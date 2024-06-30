
## A lightning introduction to Injection

As it says in the README.md, using a feature of Apple's linker Code Injection
allows you to update the implementation (i.e. body) of functions in your
app without having to relauch it. There are three parts to implementing
this functionality. Recompiling your source file and preparing a dynamic
library, loading the dynamic library and stitching the new implementations
into your running program and arranging for the new implementations to be
called to you can see on the screen that your code changes have taken effect.
The first part is implemented by the InjectionNext.app that runs on the menu 
bar, the second and third by code in the InjectionNext Swift package which
you add to the project you want to be able to inject. On startup the Swift 
package creates a socket connection to the InjectionNext.app so it can
be controlled by it and instructed to load dynamic libaries either shared
with it on the filesystem or received through the socket connection for
real devices.

### Preparing the dynamic library

InjectionNext comes with a new solution to this problem. It integrates with
Xcode which if you launch it using the app (with SourceKit logging enabled)
provides all the information you need to recompile a file with the user's 
changes which is the first step. The object file created by the recompilation
is then linked in a reasonably generic way to create a dyanmic library which
can be loaded into your program at run time using dlopen().

### Loading and binding the dynamic library

When a new dynamic library is available, the InjectionNext.app messages the
code in the InjectionNext swift package to load it and "bind" it. Binding is
the means by which a call site in your program is dispatched to the implementing
function and when you use the "Other Linker Flags", "-Xlinker -interposable"
this disptach is indirect through a writable section of memory. Change the
function pointer in this memory and your new version of code is called instead
of the old. This is done by a small piece of code from facebook named "fishhook"
and all that remains is to know the new functions just loaded in the dynamic
library. To do this you scan the "symbol table" data structures included in
the dynamic library to find the "mangled" function names. The mangled names
of Swift functions all start with "$s" and generally end in "F" or something
very similar and most of injection is simply extracting these names and the 
implementation they point to and calling fishhook to rebind them. Classes
are a ittle more complicated in that they have "vtables" in the meta-data 
describing the class but we don't need to explain that here. For Objective-C
methods there way always a public runtime API to rebind them.

### Forcing redisplay

This is the more difficult part of injection to realise. You can have the
new fuction implementtions loaded and rebound but you won't see any change in
the appearance on the screen until that new code is called. With SwiftUI the
esiest way to do this is to have an observed instance variable on your View 
struct that changes when an injection has occured. There is code to do this in
the HotSwiftUI and Inject packages if you add an @ObserveInjection property
wrapper to the View struct. It's a little more complicated for legacy
UIViewController subclasses and what needs to happen generally is 
viewDidLoad() needs to be called again each time you inject but how to arrange 
this for all currently displayed view controllers? The solution is 
InjectionNext performs a sweep all known instances of classes in the app 
and if they have been injected in the last loaded dynamic library and have an 
"@objc func injected()" method, call it. This method can call viewDidLoad()
or "configureView()" or perform any other work required to update the display.
Another approach you can use is is to "host" the view controller using the
Inject package which reinstantiates the view controller on injection.
