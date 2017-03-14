#pragma once

#include <ApplicationServices/ApplicationServices.h>

typedef int CGSConnectionID;
typedef int CGSWindowID;

typedef enum {
    kCGSOrderBelow = -1,
    kCGSOrderOut,
    kCGSOrderAbove,
    kCGSOrderIn
} CGSWindowOrderingMode;

CG_EXTERN CGSConnectionID CGSMainConnectionID(void);

CG_EXTERN CGError CGSGetScreenRectForWindow(CGSConnectionID cid, CGSWindowID wid, CGRect *outRect);
CG_EXTERN CGError CGSSetWindowLevel(CGSConnectionID cid, CGSWindowID wid, CGWindowLevel level);
CG_EXTERN CGError CGSOrderWindow(CGSConnectionID cid, CGSWindowID wid, CGSWindowOrderingMode mode, CGSWindowID relativeToWID);
