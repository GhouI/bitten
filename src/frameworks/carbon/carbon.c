/* Carbon (HIToolbox) and the pieces of CoreServices Mac apps still call:
 * Text Input Sources (TIS), UCKeyTranslate, Carbon Event handlers and
 * hot keys, LMGetKbdType, Launch Services registration and quarantine keys.
 *
 * Keyboard: one input source, the US keyboard layout. It is a CF
 * dictionary of its properties, so TISGetInputSourceProperty is a lookup
 * and CFRetain/CFRelease work on it. Its layout data
 * (kTISPropertyUnicodeKeyLayoutData) is a table of bitten's own format
 * (not Apple's 'uchr' resource), which UCKeyTranslate below reads: the
 * ANSI virtual key codes, unshifted and shifted, with Control, Caps Lock
 * and the function keys.
 *
 * Carbon events: with no window server there are no keyboard or hot-key
 * events, so handlers and hot keys are accepted, kept, and never called.
 * Written from Apple's public documentation and headers' documented
 * values. */
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "dx.h"

typedef const void *CFTypeRef;
typedef int32_t OSStatus;

enum {
    noErr = 0,
    paramErr = -50,
    eventParameterNotFoundErr = -9870,
    kUCKeyActionDown = 0, kUCKeyActionUp = 1, kUCKeyActionAutoKey = 2, kUCKeyActionDisplay = 3,
};

/* ---- CoreFoundation, by symbol ------------------------------------------ */

static void *cf(const char *name) {
    void *p = dx_registry_lookup(name);
    if (!p) dx_fatal("carbon: %s is missing", name);
    return p;
}

static CFTypeRef cfstr(const char *s) {
    CFTypeRef (*make)(const char *) = cf("___CFStringMakeConstantString");
    return make(s);
}

/* ---- constants ----------------------------------------------------------- */

#define CF_CONSTANT(name)                                                        \
    static CFTypeRef d_##name;                                                   \
    DX_EXPORT("_" #name, &d_##name)
CF_CONSTANT(kTISPropertyInputSourceCategory);
CF_CONSTANT(kTISPropertyInputSourceType);
CF_CONSTANT(kTISPropertyInputSourceIsASCIICapable);
CF_CONSTANT(kTISPropertyInputSourceIsEnableCapable);
CF_CONSTANT(kTISPropertyInputSourceIsSelectCapable);
CF_CONSTANT(kTISPropertyInputSourceIsEnabled);
CF_CONSTANT(kTISPropertyInputSourceIsSelected);
CF_CONSTANT(kTISPropertyInputSourceID);
CF_CONSTANT(kTISPropertyBundleID);
CF_CONSTANT(kTISPropertyInputModeID);
CF_CONSTANT(kTISPropertyLocalizedName);
CF_CONSTANT(kTISPropertyInputSourceLanguages);
CF_CONSTANT(kTISPropertyUnicodeKeyLayoutData);
CF_CONSTANT(kTISCategoryKeyboardInputSource);
CF_CONSTANT(kTISCategoryPaletteInputSource);
CF_CONSTANT(kTISCategoryInkInputSource);
CF_CONSTANT(kTISTypeKeyboardLayout);
CF_CONSTANT(kTISTypeKeyboardInputMethodWithoutModes);
CF_CONSTANT(kTISTypeKeyboardInputMethodModeEnabled);
CF_CONSTANT(kTISTypeKeyboardInputMode);
CF_CONSTANT(kTISTypeCharacterPalette);
CF_CONSTANT(kTISTypeKeyboardViewer);
CF_CONSTANT(kTISTypeInk);
CF_CONSTANT(kTISNotifySelectedKeyboardInputSourceChanged);
CF_CONSTANT(kTISNotifyEnabledKeyboardInputSourcesChanged);
CF_CONSTANT(kLSQuarantineAgentNameKey);
CF_CONSTANT(kLSQuarantineAgentBundleIdentifierKey);
CF_CONSTANT(kLSQuarantineTimeStampKey);
CF_CONSTANT(kLSQuarantineTypeKey);
CF_CONSTANT(kLSQuarantineTypeWebDownload);
CF_CONSTANT(kLSQuarantineTypeOtherDownload);
CF_CONSTANT(kLSQuarantineTypeEmailAttachment);
CF_CONSTANT(kLSQuarantineTypeInstantMessageAttachment);
CF_CONSTANT(kLSQuarantineTypeCalendarEventAttachment);
CF_CONSTANT(kLSQuarantineTypeOtherAttachment);
CF_CONSTANT(kLSQuarantineOriginURLKey);
CF_CONSTANT(kLSQuarantineDataURLKey);

/* Values as Apple's frameworks define them. */
__attribute__((constructor)) static void carbon_constants(void) {
#define SET(name, value) d_##name = cfstr(value)
    SET(kTISPropertyInputSourceCategory, "TISPropertyInputSourceCategory");
    SET(kTISPropertyInputSourceType, "TISPropertyInputSourceType");
    SET(kTISPropertyInputSourceIsASCIICapable, "TISPropertyInputSourceIsASCIICapable");
    SET(kTISPropertyInputSourceIsEnableCapable, "TISPropertyInputSourceIsEnableCapable");
    SET(kTISPropertyInputSourceIsSelectCapable, "TISPropertyInputSourceIsSelectCapable");
    SET(kTISPropertyInputSourceIsEnabled, "TISPropertyInputSourceIsEnabled");
    SET(kTISPropertyInputSourceIsSelected, "TISPropertyInputSourceIsSelected");
    SET(kTISPropertyInputSourceID, "TISPropertyInputSourceID");
    SET(kTISPropertyBundleID, "TISPropertyBundleID");
    SET(kTISPropertyInputModeID, "TISPropertyInputModeID");
    SET(kTISPropertyLocalizedName, "TISPropertyLocalizedName");
    SET(kTISPropertyInputSourceLanguages, "TISPropertyInputSourceLanguages");
    SET(kTISPropertyUnicodeKeyLayoutData, "TISPropertyUnicodeKeyLayoutData");
    SET(kTISCategoryKeyboardInputSource, "TISCategoryKeyboardInputSource");
    SET(kTISCategoryPaletteInputSource, "TISCategoryPaletteInputSource");
    SET(kTISCategoryInkInputSource, "TISCategoryInkInputSource");
    SET(kTISTypeKeyboardLayout, "TISTypeKeyboardLayout");
    SET(kTISTypeKeyboardInputMethodWithoutModes, "TISTypeKeyboardInputMethodWithoutModes");
    SET(kTISTypeKeyboardInputMethodModeEnabled, "TISTypeKeyboardInputMethodModeEnabled");
    SET(kTISTypeKeyboardInputMode, "TISTypeKeyboardInputMode");
    SET(kTISTypeCharacterPalette, "TISTypeCharacterPalette");
    SET(kTISTypeKeyboardViewer, "TISTypeKeyboardViewer");
    SET(kTISTypeInk, "TISTypeInk");
    SET(kTISNotifySelectedKeyboardInputSourceChanged, "AppleSelectedInputSourcesChangedNotification");
    SET(kTISNotifyEnabledKeyboardInputSourcesChanged, "AppleEnabledInputSourcesChangedNotification");
    SET(kLSQuarantineAgentNameKey, "LSQuarantineAgentName");
    SET(kLSQuarantineAgentBundleIdentifierKey, "LSQuarantineAgentBundleIdentifier");
    SET(kLSQuarantineTimeStampKey, "LSQuarantineTimeStamp");
    SET(kLSQuarantineTypeKey, "LSQuarantineType");
    SET(kLSQuarantineTypeWebDownload, "LSQuarantineTypeWebDownload");
    SET(kLSQuarantineTypeOtherDownload, "LSQuarantineTypeOtherDownload");
    SET(kLSQuarantineTypeEmailAttachment, "LSQuarantineTypeEmailAttachment");
    SET(kLSQuarantineTypeInstantMessageAttachment, "LSQuarantineTypeInstantMessageAttachment");
    SET(kLSQuarantineTypeCalendarEventAttachment, "LSQuarantineTypeCalendarEventAttachment");
    SET(kLSQuarantineTypeOtherAttachment, "LSQuarantineTypeOtherAttachment");
    SET(kLSQuarantineOriginURLKey, "LSQuarantineOriginURL");
    SET(kLSQuarantineDataURLKey, "LSQuarantineDataURL");
#undef SET
}

/* ---- the US keyboard layout ------------------------------------------- */

/* Characters for the ANSI virtual key codes (kVK_ANSI_* and friends),
 * unshifted and shifted. 0 means no character. */
static const char US_PLAIN[128] = {
    [0] = 'a', [1] = 's', [2] = 'd', [3] = 'f', [4] = 'h', [5] = 'g', [6] = 'z', [7] = 'x',
    [8] = 'c', [9] = 'v', [10] = '\xa7', [11] = 'b', [12] = 'q', [13] = 'w', [14] = 'e', [15] = 'r',
    [16] = 'y', [17] = 't', [18] = '1', [19] = '2', [20] = '3', [21] = '4', [22] = '6', [23] = '5',
    [24] = '=', [25] = '9', [26] = '7', [27] = '-', [28] = '8', [29] = '0', [30] = ']', [31] = 'o',
    [32] = 'u', [33] = '[', [34] = 'i', [35] = 'p', [36] = '\r', [37] = 'l', [38] = 'j', [39] = '\'',
    [40] = 'k', [41] = ';', [42] = '\\', [43] = ',', [44] = '/', [45] = 'n', [46] = 'm', [47] = '.',
    [48] = '\t', [49] = ' ', [50] = '`', [51] = '\b', [52] = 0x03, [53] = 0x1b,
    [65] = '.', [67] = '*', [69] = '+', [71] = 0x1b, [75] = '/', [76] = 0x03, [78] = '-', [81] = '=',
    [82] = '0', [83] = '1', [84] = '2', [85] = '3', [86] = '4', [87] = '5', [88] = '6', [89] = '7',
    [91] = '8', [92] = '9',
    [96] = 0x10, [97] = 0x10, [98] = 0x10, [99] = 0x10, [100] = 0x10, [101] = 0x10, [103] = 0x10,
    [105] = 0x10, [107] = 0x10, [109] = 0x10, [111] = 0x10, [113] = 0x10, [114] = 0x05,
    [115] = 0x01, [116] = 0x0b, [117] = 0x7f, [118] = 0x10, [119] = 0x04, [120] = 0x10,
    [121] = 0x0c, [122] = 0x10, [123] = 0x1c, [124] = 0x1d, [125] = 0x1f, [126] = 0x1e,
};

static const char US_SHIFT_DIGITS[] = ")!@#$%^&*(";

static char us_shifted(int code) {
    char c = US_PLAIN[code];
    if (c >= 'a' && c <= 'z') return (char)(c - 32);
    if (c >= '0' && c <= '9' && code < 30) return US_SHIFT_DIGITS[c - '0'];
    switch (c) {
    case '-': return '_';
    case '=': return '+';
    case '[': return '{';
    case ']': return '}';
    case '\\': return '|';
    case ';': return ':';
    case '\'': return '"';
    case ',': return code == 43 ? '<' : c;
    case '.': return code == 47 ? '>' : c;
    case '/': return code == 44 ? '?' : c;
    case '`': return '~';
    case '\xa7': return '\xb1';
    default: return c;
    }
}

/* The layout data handed out as kTISPropertyUnicodeKeyLayoutData. */
struct layout {
    char magic[8];                       /* "bittenKL" */
    uint16_t plain[128], shifted[128];
};

static void fill_layout(struct layout *l) {
    memcpy(l->magic, "bittenKL", 8);
    for (int i = 0; i < 128; i++) {
        l->plain[i] = (uint8_t)US_PLAIN[i];
        l->shifted[i] = (uint8_t)us_shifted(i);
    }
}

static OSStatus d_UCKeyTranslate(const void *layout, uint16_t code, uint16_t action, uint32_t modifiers,
                                 uint32_t keyboardType, uint32_t options, uint32_t *deadKeyState,
                                 unsigned long maxLength, unsigned long *actualLength, uint16_t *out) {
    const struct layout *l = layout;
    if (!l || memcmp(l->magic, "bittenKL", 8) || !actualLength) return paramErr;
    if (deadKeyState) *deadKeyState = 0;
    *actualLength = 0;
    if (action == kUCKeyActionUp || code >= 128) return noErr;
    /* modifierKeyState is (EventModifiers >> 8) & 0xff: cmd 1, shift 2,
     * caps lock 4, option 8, control 16. */
    int shift = (modifiers & 2) != 0, caps = (modifiers & 4) != 0, control = (modifiers & 16) != 0;
    uint16_t ch = shift ? l->shifted[code] : l->plain[code];
    if (caps && !shift && ch >= 'a' && ch <= 'z') ch -= 32;
    if (control) {
        uint16_t base = l->plain[code];
        if (base >= 'a' && base <= 'z') ch = (uint16_t)(base - 'a' + 1);
        else if (base == '[') ch = 0x1b;
        else if (base == '\\') ch = 0x1c;
        else if (base == ']') ch = 0x1d;
    }
    if (!ch) return noErr;
    if (maxLength < 1 || !out) return paramErr;
    out[0] = ch;
    *actualLength = 1;
    return noErr;
}
DX_FN(UCKeyTranslate);

/* ---- Text Input Sources ------------------------------------------------- */

static CFTypeRef us_source;
static pthread_once_t us_once = PTHREAD_ONCE_INIT;

static void make_us_source(void) {
    void *(*create_mutable)(CFTypeRef, long, const void *, const void *) = cf("_CFDictionaryCreateMutable");
    void (*set)(void *, CFTypeRef, CFTypeRef) = cf("_CFDictionarySetValue");
    CFTypeRef (*array)(CFTypeRef, const void **, long, const void *) = cf("_CFArrayCreate");
    CFTypeRef (*data)(CFTypeRef, const void *, long) = cf("_CFDataCreate");
    CFTypeRef yes = *(CFTypeRef *)cf("_kCFBooleanTrue");
    void *d = create_mutable(NULL, 0, cf("_kCFTypeDictionaryKeyCallBacks"), cf("_kCFTypeDictionaryValueCallBacks"));
    struct layout l;
    fill_layout(&l);
    const void *languages[] = {cfstr("en")};
    set(d, d_kTISPropertyInputSourceID, cfstr("com.apple.keylayout.US"));
    set(d, d_kTISPropertyLocalizedName, cfstr("U.S."));
    set(d, d_kTISPropertyInputSourceCategory, d_kTISCategoryKeyboardInputSource);
    set(d, d_kTISPropertyInputSourceType, d_kTISTypeKeyboardLayout);
    set(d, d_kTISPropertyInputSourceIsASCIICapable, yes);
    set(d, d_kTISPropertyInputSourceIsEnableCapable, yes);
    set(d, d_kTISPropertyInputSourceIsSelectCapable, yes);
    set(d, d_kTISPropertyInputSourceIsEnabled, yes);
    set(d, d_kTISPropertyInputSourceIsSelected, yes);
    set(d, d_kTISPropertyInputSourceLanguages, array(NULL, languages, 1, cf("_kCFTypeArrayCallBacks")));
    set(d, d_kTISPropertyUnicodeKeyLayoutData, data(NULL, &l, sizeof l));
    us_source = d;
}

static CFTypeRef copy_us_source(void) {
    pthread_once(&us_once, make_us_source);
    CFTypeRef (*retain)(CFTypeRef) = cf("_CFRetain");
    return retain(us_source);
}

static CFTypeRef d_TISCopyCurrentKeyboardLayoutInputSource(void) { return copy_us_source(); }
DX_FN(TISCopyCurrentKeyboardLayoutInputSource);
static CFTypeRef d_TISCopyCurrentKeyboardInputSource(void) { return copy_us_source(); }
DX_FN(TISCopyCurrentKeyboardInputSource);
static CFTypeRef d_TISCopyCurrentASCIICapableKeyboardLayoutInputSource(void) { return copy_us_source(); }
DX_FN(TISCopyCurrentASCIICapableKeyboardLayoutInputSource);
static CFTypeRef d_TISCopyCurrentASCIICapableKeyboardInputSource(void) { return copy_us_source(); }
DX_FN(TISCopyCurrentASCIICapableKeyboardInputSource);
static CFTypeRef d_TISCopyInputSourceForLanguage(CFTypeRef language) { return copy_us_source(); }
DX_FN(TISCopyInputSourceForLanguage);

static CFTypeRef d_TISGetInputSourceProperty(CFTypeRef source, CFTypeRef key) {
    if (!source || !key) return NULL;
    CFTypeRef (*get)(CFTypeRef, CFTypeRef) = cf("_CFDictionaryGetValue");
    return get(source, key);
}
DX_FN(TISGetInputSourceProperty);

/* The list of sources: just the one, whatever the filter asks. */
static CFTypeRef d_TISCreateInputSourceList(CFTypeRef properties, unsigned char includeAllInstalled) {
    CFTypeRef (*array)(CFTypeRef, const void **, long, const void *) = cf("_CFArrayCreate");
    CFTypeRef src = copy_us_source();
    CFTypeRef list = array(NULL, &src, 1, cf("_kCFTypeArrayCallBacks"));
    void (*release)(CFTypeRef) = cf("_CFRelease");
    release(src);
    return list;
}
DX_FN(TISCreateInputSourceList);

static OSStatus d_TISSelectInputSource(CFTypeRef source) { return noErr; }
DX_FN(TISSelectInputSource);
static OSStatus d_TISEnableInputSource(CFTypeRef source) { return noErr; }
DX_FN(TISEnableInputSource);

/* An ADB-era keyboard type number: 40 is the ANSI extended keyboard. */
static uint8_t d_LMGetKbdType(void) { return 40; }
DX_FN(LMGetKbdType);

/* ---- Carbon events and hot keys ------------------------------------------ */

struct event_handler { void *target, *proc, *user; };
struct hot_key { uint32_t code, modifiers; uint64_t id; };

static int application_target, dispatcher_target;

static void *d_GetApplicationEventTarget(void) { return &application_target; }
DX_FN(GetApplicationEventTarget);
static void *d_GetEventDispatcherTarget(void) { return &dispatcher_target; }
DX_FN(GetEventDispatcherTarget);

static OSStatus d_InstallEventHandler(void *target, void *proc, unsigned long count, const void *types,
                                      void *user, struct event_handler **out) {
    if (!target || !proc) return paramErr;
    struct event_handler *h = calloc(1, sizeof *h);
    if (!h) return -108;                                  /* memFullErr */
    h->target = target;
    h->proc = proc;
    h->user = user;
    if (out) *out = h;
    return noErr;
}
DX_FN(InstallEventHandler);

static OSStatus d_RemoveEventHandler(struct event_handler *h) {
    free(h);
    return noErr;
}
DX_FN(RemoveEventHandler);

/* EventHotKeyID {OSType signature; UInt32 id} travels in one register. */
static OSStatus d_RegisterEventHotKey(uint32_t code, uint32_t modifiers, uint64_t id, void *target,
                                      uint32_t options, struct hot_key **out) {
    struct hot_key *k = calloc(1, sizeof *k);
    if (!k) return -108;
    k->code = code;
    k->modifiers = modifiers;
    k->id = id;
    if (out) *out = k;
    return noErr;
}
DX_FN(RegisterEventHotKey);

static OSStatus d_UnregisterEventHotKey(struct hot_key *k) {
    free(k);
    return noErr;
}
DX_FN(UnregisterEventHotKey);

/* No event ever reaches a handler, so no event has parameters. */
static OSStatus d_GetEventParameter(void *event, uint32_t name, uint32_t type, uint32_t *actualType,
                                    unsigned long size, unsigned long *actualSize, void *data) {
    return eventParameterNotFoundErr;
}
DX_FN(GetEventParameter);

static uint32_t d_GetEventClass(void *event) { return 0; }
DX_FN(GetEventClass);
static uint32_t d_GetEventKind(void *event) { return 0; }
DX_FN(GetEventKind);

/* ---- Launch Services ------------------------------------------------------ */

/* Registration is how an app tells Launch Services where it lives; there
 * is no Launch Services database here, so it succeeds and records
 * nothing. */
static OSStatus d_LSRegisterURL(CFTypeRef url, unsigned char update) { return noErr; }
DX_FN(LSRegisterURL);
