#import <Foundation/Foundation.h>
#import "commandLineArguments.h"
#import "wiggleMethod.h"
#import <string.h>
#import <getopt.h>

bool parseCommandLineArgs(CommandLineArgs *args, int argc, const char *argv[])
{
    bool showUsage = false, showVersion = false;
    char *end;
    int c;
    unsigned long val;
    NSOperatingSystemVersion systemVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    
    memset(args, 0, sizeof(*args));
    
    if (systemVersion.minorVersion < 13) {
        args->method = kMethodDrag;
    } else {
        args->method = kMethodCursorPosition;
    }
    
    args->wiggleDuration = kWiggleDefaultDurationMS;
    
    for(int i = 0; i < argc; ++i) {
        printf("arg %d: %s\n", i, argv[i]);
    }
    
    while (1) {
        static struct option longOptions[] = {
            {"help", no_argument, NULL, 'h'},
            {"version", no_argument, NULL, 'v'},
            {"daemon", no_argument, NULL, 'd'},
            {"release", no_argument, NULL, 'r'},
            {"method", required_argument, NULL, 'm'},
            {"wiggle-duration", required_argument, NULL, 'w'},
            {"internal-drag",  no_argument, NULL, 'i'},
            {"daemonized",  no_argument, NULL, 1},
            {NULL, 0, NULL, 0}
        };
        
        int optionIndex = 0;
        
        c = getopt_long(argc, (char * const *)argv, "hvdrm:w:i", longOptions, &optionIndex);
        
        /* Detect the end of the options. */
        if (c == -1) {
            break;
        }
        
        switch(c) {
            case 'h':
                showUsage = true;
                break;
            case 'v':
                showVersion = true;
                break;
            case 'd':
                args->daemon = true;
                break;
            case 1:
                args->daemonized = true;
                break;
            case 'r':
                args->release = true;
                break;
            case 'm':
                if (strcmp(optarg, "wiggle") == 0) {
                    args->method = kMethodWiggle;
                } else if (strcmp(optarg, "drag") == 0) {
                    args->method = kMethodDrag;
                } else if (strcmp(optarg, "cursor") == 0) {
                    args->method = kMethodCursorPosition;
                } else {
                    showUsage = true;
                }
                break;
            case 'w':
                val = strtoul(optarg, &end, 10);
                
                if (val == 0 || val == ULONG_MAX || val > 1000) {
                    showUsage = true;
                } else {
                    args->wiggleDuration = (int)val;
                }
                break;
            case 'i':
                args->internalMouseDown = true;
                break;
            case '?':
                showUsage = true;
                break;
        }
    }
    
    if (showUsage) {
        // wrapping at 80 columns:
        //      01234567890123456789012345678901234567890123456789012345678901234567890123456789
        printf("Usage: missionControlFullDesktopBar [options]\n");
        printf("\n");
        printf("Options:\n");
        printf("  -d, --daemon                      Runs the program as a daemon. Will fork,\n");
        printf("                                    trigger Mission Control with the options\n");
        printf("                                    specified, and then continue running. Any\n");
        printf("                                    further executions will cause the daemon\n");
        printf("                                    process to invoke Mission Control again as\n");
        printf("                                    long as it continues to run. Useful because\n");
        printf("                                    it makes invoking Mission Control more\n");
        printf("                                    responsive and allows using the -r /\n");
        printf("                                    --release option. Note that you can specify\n");
        printf("                                    this flag when a daemon is already running,\n");
        printf("                                    and it will not spawn another daemon.\n");
        printf("  -r, --release                     Indicates that a button that should trigger\n");
        printf("                                    Mission Control has been released. Basically\n");
        printf("                                    if this option is used within 500 ms of\n");
        printf("                                    invoking Mission Control, will uninvoke\n");
        printf("                                    Mission Control, otherwise nothing happens.\n");
        printf("                                    Only has an effect when used with a daemon.\n");
        printf("                                    process. All other options have no effect\n");
        printf("                                    when used with -r / --release.\n");
        printf("  -m, --method <wiggle/drag/cursor> Selects the method to use. Current options\n");
        printf("                                    are wiggle, drag, cursor. Defaults to drag\n");
        printf("                                    for macOS 10.12, cursor for 10.13 and later.\n");
        printf("                                    Note that the cursor method does not work in\n");
        printf("                                    macOS 10.12.\n");
        printf("  -w, --wiggle-duration <duration>  When wiggle method is used, specifies how\n");
        printf("                                    many milliseconds the wiggle will last. Max\n");
        printf("                                    value is 1000. Defaults to %d.\n", kWiggleDefaultDurationMS);
        printf("  -i, --internal-drag               When drag method is used, uses faster and\n");
        printf("                                    more reliable internal drag that does not\n");
        printf("                                    involve creating a system-wide mouse event,\n");
        printf("                                    though it *may* create weird side effects.\n");
        printf("                                    Has no effect unless used with a daemon\n");
        printf("                                    process.\n");
        printf("  -h, --help                        Displays this help message\n");
        printf("  -v, --version                     Displays program version\n");
        return false;
    } else if (showVersion) {
        NSString *version = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"];
        printf("%s %s\n", PROGRAM_NAME, [version UTF8String]);
        return false;
    }
    
    return true;
}
