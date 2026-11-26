/* bitten SDK: window-server queries and CGEvent (no window server: empty
 * window lists, no input). */
#ifndef BITTEN_CGWINDOW_H
#define BITTEN_CGWINDOW_H
#include <CoreGraphics/CGBase.h>

CG_ASSUME_BEGIN
typedef uint32_t CGWindowID;
typedef CG_OPTIONS(uint32_t, CGWindowListOption) {
    kCGWindowListOptionAll = 0, kCGWindowListOptionOnScreenOnly = 1, kCGWindowListOptionOnScreenAboveWindow = 2,
    kCGWindowListOptionOnScreenBelowWindow = 4, kCGWindowListOptionIncludingWindow = 8,
    kCGWindowListExcludeDesktopElements = 16,
};
CG_EXTERN const CFStringRef kCGWindowNumber, kCGWindowStoreType, kCGWindowLayer, kCGWindowBounds,
    kCGWindowSharingState, kCGWindowAlpha, kCGWindowOwnerPID, kCGWindowMemoryUsage, kCGWindowOwnerName,
    kCGWindowName, kCGWindowIsOnscreen, kCGWindowBackingLocationVideoMemory;
CFArrayRef _Nullable CGWindowListCopyWindowInfo(CGWindowListOption option, CGWindowID relativeToWindow);

typedef struct CG_BRIDGED_TYPE(id) __CGEvent *CGEventRef;
typedef struct CG_BRIDGED_TYPE(id) __CGEventSource *CGEventSourceRef;
typedef CG_ENUM(int32_t, CGEventSourceStateID) {
    kCGEventSourceStatePrivate = -1, kCGEventSourceStateCombinedSessionState = 0, kCGEventSourceStateHIDSystemState = 1,
};
typedef uint32_t CGEventType;
typedef uint32_t CGEventField;
typedef uint32_t CGMouseButton;
typedef uint64_t CGEventFlags;
typedef uint16_t CGKeyCode;
typedef uint32_t CGEventTapLocation;

CFTypeID CGEventGetTypeID(void);
CGEventRef _Nullable CGEventCreate(CGEventSourceRef _Nullable source);
CGEventRef _Nullable CGEventCreateCopy(CGEventRef _Nullable event);
CGEventRef _Nullable CGEventCreateKeyboardEvent(CGEventSourceRef _Nullable source, CGKeyCode key, bool keyDown);
CGEventRef _Nullable CGEventCreateMouseEvent(CGEventSourceRef _Nullable source, CGEventType type, CGPoint position, CGMouseButton button);
CGEventType CGEventGetType(CGEventRef _Nullable event);
void CGEventSetType(CGEventRef _Nullable event, CGEventType type);
CGEventFlags CGEventGetFlags(CGEventRef _Nullable event);
void CGEventSetFlags(CGEventRef _Nullable event, CGEventFlags flags);
CGPoint CGEventGetLocation(CGEventRef _Nullable event);
void CGEventSetLocation(CGEventRef _Nullable event, CGPoint location);
int64_t CGEventGetIntegerValueField(CGEventRef _Nullable event, CGEventField field);
void CGEventSetIntegerValueField(CGEventRef _Nullable event, CGEventField field, int64_t value);
double CGEventGetDoubleValueField(CGEventRef _Nullable event, CGEventField field);
void CGEventSetDoubleValueField(CGEventRef _Nullable event, CGEventField field, double value);
void CGEventPost(CGEventTapLocation tap, CGEventRef _Nullable event);
bool CGEventSourceButtonState(CGEventSourceStateID stateID, CGMouseButton button);
bool CGEventSourceKeyState(CGEventSourceStateID stateID, CGKeyCode key);
CGEventFlags CGEventSourceFlagsState(CGEventSourceStateID stateID);
double CGEventSourceSecondsSinceLastEventType(CGEventSourceStateID stateID, CGEventType eventType);
CG_ASSUME_END
#endif
