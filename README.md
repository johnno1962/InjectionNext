# InjectionNext

### The fourth evolution of Code Injection for Xcode

Using a feature of Apple's linker this implementation of Code Injection
allows you to update the implementation (i.e. body) of functions in your
app without having to relaunch it. This can save a developer a significant
amount of time tweaking code or iterating over a design.

This repo is a refresh of the [InjectionIII](https://github.com/johnno1962/InjectionIII)
app that uses different techniques to determine how to rebuild source files
that should be faster and more reliable for very large projects. With versions 
1.3.0+ the only changes that are required to your project are to add the 
following "Other Linker Flags" to your project's **Debug** build settings:

![Icon](App/interposable.png)

That last flag is to link what were bundles in InjectionIII as a dynamic library:

`/Applications/InjectionNext.app/Contents/Resources/lib$(PLATFORM_NAME)Injection.dylib`

If you want to inject on a device you'll also need to add the following
as a "Run Script/Build Phase" of your main target to copy the required
libraries into your app bundle (for a Debug build) and toggle "Enable Devices"
to open a network port for incoming connections from your client app.

```
export RESOURCES="/Applications/InjectionNext.app/Contents/Resources"
if [ -f "$RESOURCES/copy_bundle.sh" ]; then
    "$RESOURCES/copy_bundle.sh"
fi
```
The basic MO is to build the app in the `App` directory, or download one of 
the binary releases in this repo, move it /Applications, quit Xcode and run the
resulting `InjectionNext.app` and use that to re-launch Xcode using the menu item 
`Launch Xcode` from the status bar. No more code changes required to load binary 
code bundles etc. Your code changes take effect
when you save a source for an app that has this package as a dependency
and has connected to the InjectionNext app which has launched Xcode.

**Please note:** you can only inject changes to code inside a function body
and you can not add/remove or rename properties with storage or add or 
reorder methods in a non final class or change function signatures.

To inject SwiftUI sucessfully a couple of minor code changes to each View are 
required. Consult the https://github.com/johnno1962/HotSwiftUI README or you
can make these changes automatically using the menu item "Prepare SwiftUI/".
For SwiftUI you would also generally also integrate either the
[Inject](https://github.com/krzysztofzablocki/Inject) or
[HotSwiftUI](https://github.com/johnno1962/HotSwiftUI) package into your project. 

When your app runs it should connect to the `InjectionNext.app` and it's icon
change to orange. After that, by parsing the messages from the "supervised"
launch of Xcode it is possible to know when files are saved and exactly how
to recompile them for injection. Injection on a device uses the same 
configuration but is opt-in through the menu item "Enable Devices"
(as it needs to open a network port). You also need to select the 
project's "expanded codesigning identity" from the codesigning
phase of your build logs in the window that pops up. Sometimes a 
device will not connect to the app first time after unlocking it.
If at first it doesn't succeed, try again.

The colours of the menu bar icon bar correspond to:

* Blue when you first run the InjectionNext app.
* Purple when you have launched Xcode using the app.
* Orange when your client app has connected to it.
* Green while it is recompiling a saved source.
* Yellow if the source has failed to compile.

The binary dylibs also integrate [Nimble](https://github.com/Quick/Nimble)
and a slightly modified version of the [Quick](https://github.com/Quick/Quick) 
testing framework to inhibit spec caching under their respective Apache licences.

To inject tests on a device: when enabling the
"Enable Devices" menu item, select "Enable testing on device" which 
will add the arguments shown to the link of each dynamic library. 
As you do this, the command above will be inserted into the clipboard 
which you should add to your project as a "Run Script" "Build Phase" 
of the main target to copy the required libraries into the app bundle.

### Cursor/VSCode mode.

If you would like to use InjectionNext with the Cursor code editor,
you can have it fall back to InjectionIII-style log parsing using
the "...or Watch Project" menu item to select the project root
you will be working under (or use the new "Proxy" mode below
for Swift projects.) In this case, you shouldn't launch 
Xcode from inside the InjectionNext.app but you'll need to have 
built your app in Xcode at some point in the past for the logs
to be available. You should build using the same version as that 
selected by `xcode-select`. With Xcode 16.3+, for this log parsing
mode to continue working you'll need to add a custom build setting
EMIT_FRONTEND_COMMAND_LINES.

### New compiler "proxy" mode.

It is also possible to intercept swift compilation commands as a new proof of
concept for when at some point in the future these are no longer captured in 
the Xcode logs (as was the case with Xcode 16.3 beta1). In this case, select 
"Intercept compiler" to patch the current toolchain slightly to capture all
compilations using a script and send them to the InjectionNext.app. Once this 
patch has been applied you don't need to launch Xcode from the app and you can 
inject by starting a file watcher using the "...or Watch Project" menu item
(though this should happen automatically when you recompile Swift sources).

So, InjectionNext has three ways in which it can operate of which the newest and 
the simplest one if you're prepared to patch your toolchain is the "proxy" mode.
The original mode of operation launching Xcode inside the app takes preference 
and, if you have selected a file watcher and are intercepting the compiler
commands that is the next preference followed by the log parsing fallback using
the [InjectionLite](https://github.com/johnno1962/InjectionLite) package which 
essentially works as InjectionIII did when the logs are available.

For more information consult the [original InjectionIII README](https://github.com/johnno1962/InjectionIII)
or for the bigger picture see [this swift evolution post](https://forums.swift.org/t/weve-been-doing-it-wrong-all-this-time/72015).

You can run InjectionNext from the command line and have it open
your project in Xcode automatically using the -projectPath option.

    open -a InjectionNext --args -projectPath /path/to/project

Set a user default with the same name if you want to always open 
this project inside the selected Xcode on launching the app.

The fabulous app icon is thanks to Katya of [pixel-mixer.com](http://pixel-mixer.com/).
