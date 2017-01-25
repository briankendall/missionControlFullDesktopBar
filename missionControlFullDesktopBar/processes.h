
#ifndef processes_h
#define processes_h

enum {
    kSuccess = 0,
    kCouldNotFindRequestedProcess = -1, 
    kInvalidArgumentsError = -2,
    kErrorGettingSizeOfBufferRequired = -3,
    kUnableToAllocateMemoryForBuffer = -4,
    kPIDBufferOverrunError = -5
};

int getCountOfProcessesWithName(const char* ProcessName, 
                                unsigned int* NumberOfMatchesFound,
                                int* SysctlError);


#endif /* processes_h */
