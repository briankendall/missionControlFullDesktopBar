#ifndef commandLineArguments_h
#define commandLineArguments_h

enum {
    kMethodNone = 0,
    kMethodWiggle = 1,
    kMethodDrag = 2,
    kMethodCursorPosition = 3
};

typedef struct _CommandLineArgs {
    bool daemon;
    bool daemonized;
    bool release;
    int method;
    int wiggleDuration;
    bool internalMouseDown;
} CommandLineArgs;

bool parseCommandLineArgs(CommandLineArgs *args, int argc, const char *argv[]);

#endif /* commandLineArguments_h */
