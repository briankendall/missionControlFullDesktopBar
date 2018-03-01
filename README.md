# missionControlFullDesktopBar

An application that invokes Mission Control in a manner that causes all of the desktop previews to be present immediately like they were in macOS 10.10 and earlier, rather than requiring the user to mouse over them. This is accomplished using one of two incredibly hacky and unsavory methods.

It's intended to be a replacement for [forceFullDesktopBar](https://github.com/briankendall/forceFullDesktopBar) as it seems unlikely that method will ever be able to work in macOS 10.12 and later. While this app may work in macOS 10.11, I personally haven't tested it and you should just use [forceFullDesktopBar](https://github.com/briankendall/forceFullDesktopBar) because it will work a lot better.

## Quick start

As this app works similarly to the Mission Control application provided by Apple, it's intended to be used by an application that can bind a terminal command to a mouse button, keystroke, or trackpad gesture. I recommend [BetterTouchTool](http://bettertouchtool.net).

To use it, bind whichever kind of input you want to a terminal command that looks something like this:

    /path/to/missionControlFullDesktopBar.app/Contents/MacOS/missionControlFullDesktopBar -d -i
    
The `-d` and `-i` options generally result in the best performance and reliability. (More about that later.)

If you're binding it to a mouse button or keystroke, I recommend making it so that the above command is executed when the button is pressed, and the following command is executed when it's released:

    /path/to/missionControlFullDesktopBar.app/Contents/MacOS/missionControlFullDesktopBar -d -r

This will allow you to both:

* Press and hold the button to enter Mission Control, and then release it to exit Mission Control.
* Press the button quickly to toggle Mission Control

On first run, you may need to grant it permission to control the computer using the Security & Privacy system preferences.

## How it works

There are two methods I've discovered for triggering Mission Control with the full desktop bar. 

### The Wiggle Method:

The first is the more obvious method of having the mouse move over the desktop bar, and that's what the "wiggle" method is. When used, right as Mission Control is triggered the mouse will wiggle in the upper left corner of the primary display for 120 milliseconds (or a different duration if you want), and then pop the cursor back to where it was before. Any mouse movement during this time is recorded so that the cursor will appear in the place you expect it, rather than the exact position it was in when you triggered Mission Control. The whole experience should be relatively seamless.

##### Advantages:
1. Not quite as hacky as the "drag" method.
2. Less likely to incur strange side effects

##### Disadvantages:
1. Slower: you can see the animation of the full desktop bar appearing
2. The cursor looks like it disappears briefly
3. Requires proper timing: if Mission Control takes too long to invoke, the wiggling may not register and then you get the crappy Mission Control without the desktop previews.
4. Bugs or unexpected situations may cause the mouse cursor to remain in the upper left corner of your screen, which would be pretty annoying!

### The Drag Method:

There's another way to get Mission Control to have the full desktop bar, which is to have a drag be in progress. It can be a window, a Finder icon, a bit of text, or really anything else. The drag method takes advantage of this. When triggered, the app will create a small, invisible window directly under the cursor, create an artificial mouse down event, and as soon as that mouse down is registered in the window, start a drag operation for an empty string of text and invoke Mission Control. As soon as Mission Control is invoked, the app releases the mouse button, thus ending the drag. If all goes well this whole process should be completely invisible to the user.

Furthermore, it's possible for an app to send its own windows a mouse event directly, bypassing the systemwide event queue. When used with the drag method, this has the advantage of not even requiring the invisible window to be on screen and properly clickable, making the entire operation faster and more reliable. For the purposes of this app, this is called an "internal drag", as the fake drag operation happens entirely within the confines of the app.

##### Advantages:
1. Cleaner: there is no transition animation of the desktop previews appearing. They're present from the moment Mission Control is invoked.
2. More reliable: the cursor doesn't move anywhere, so there's no chance of it getting stuck in the upper left corner, and no issues with proper timing.
3. When the "internal drag" option is used, it's the most reliable method as there's not really anything that can interfere with the fake drag occurring.

##### Disadvantages:
1. Doesn't work if Mission Control is invoked while the mouse is down. This is because this method cannot be used if a real drag is in progress, as there's no way to detect that situation (that I'm presently aware of). So if the mouse is down, the app will invoke Mission Control normally.
2. Is very hacky! Messing about with invisible windows, undocumented APIs, and fake drag operations may cause unintented side effects.
3. If the "internal drag" option is used, it's the most hacky! (Though I personally haven't noticed any strange side effects from it so far.)

Since the drag method typically works better, it's the default option when the app is launched.

## Command Line Options

This app has the following important command line options:

* `-d / --daemon`    
Runs the program as a daemon. This causes the process to fork, trigger Mission Control with the options you've specified, and then continue running. Any further executions will cause the daemon process to invoke Mission Control again as long as it continues to run. This is useful because it makes invoking Mission Control more responsive, as the process doesn't need to create the resources it needs every single time it runs. This applies particularly when using the "drag" method. It also allows using the -r / --release option. Note that you can specify this flag when a daemon is already running, and it will not spawn another daemon.
* `-r / --release`    
Indicates that a button, keystroke, or whatever that should trigger Mission Control has been released. Basically if this option is used within 500 ms of invoking Mission Control, will uninvoke Mission Control, otherwise nothing happens. Only has an effect when used with a daemon process. All other options have no effect when used with -r / --release.
* `-m / --method \<wiggle/drag\>`    
Selects which method to use to invoke Mission Control with the full desktop bar. Current options are wiggle and drag. The default is drag. See above for a more thorough explanation of what these methods are and the consequences of using them.
* `-w / --wiggle-duration <duration>`    
When the wiggle method is used, specifies how many milliseconds the wiggling will last. Defaults to 120 ms, and the maximum is 1000 ms.
* `-i / --internal-drag`    
When the drag method is used, the app will use a faster and more reliable method of triggering the drag that involves sending its own window a mouse event, bypassing the system's event queue and ensuring that the window will receive the mouse event regardless of where on screen it is and what may be covering it. However, it may cause some weird side effects, because it's really, *really* hacky. Has no effect unless used with a daemon process, as the first invocation of Mission Control using the drag method always uses a system-wide mouse event.

## Troubleshooting

If something goes wrong, and I'd like to say that it's quite likely something *will* go wrong given how incredibly hacky this app is, then I recommend changing how the app is executed to see if any of the other options for better for you.

If you notice strange side effects when using the "drag" method, try excluding the `-i` option.

If you still notice strange side effects when using the "drag" method, or it otherwise doesn't work properly, try switching to the "wiggle" method, i.e. use the following command line options: `-d -m wiggle`

If the "wiggle" method doesn't work consistently, try increasing the wiggle duration, using options like: `-d -m wiggle -w 200`. If 200 ms doesn't work, try gradually increasing it until you find a value that does work consistently.

If it's still not working, you may be SOL. You can create an issue for the project, but I can't guarantee I'll be able to fix it. The bug you experience may not be the slightest bit reproduceable on my or anyone else's system, or it may be an unavoidable consequence of how this app works.

## Why?

See the [similar section in the read me of forceFullDesktopBar](https://github.com/briankendall/forceFullDesktopBar#why-go-through-all-of-this-trouble).

But the real answer is I like making stuff like this.
