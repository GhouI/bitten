/* Carbon and CoreServices: the keyboard input source and its layout,
 * UCKeyTranslate on the US layout, Carbon event handlers and hot keys. */
#include "darwin.h"

typedef const void *CFRef;
typedef long CFIndex;
typedef int OSStatus;

CFRef TISCopyCurrentKeyboardLayoutInputSource(void);
CFRef TISCopyCurrentKeyboardInputSource(void);
CFRef TISGetInputSourceProperty(CFRef source, CFRef key);
CFRef TISCreateInputSourceList(CFRef properties, unsigned char all);
unsigned char LMGetKbdType(void);
OSStatus UCKeyTranslate(const void *layout, unsigned short code, unsigned short action, unsigned int modifiers,
                        unsigned int keyboardType, unsigned int options, unsigned int *deadKeyState,
                        unsigned long maxLength, unsigned long *actualLength, unsigned short *out);
void *GetApplicationEventTarget(void);
OSStatus InstallEventHandler(void *target, void *proc, unsigned long count, const void *types, void *user, void **out);
OSStatus RemoveEventHandler(void *handler);
typedef struct { unsigned int signature, id; } EventHotKeyID;
OSStatus RegisterEventHotKey(unsigned int code, unsigned int modifiers, EventHotKeyID id, void *target,
                             unsigned int options, void **out);
OSStatus UnregisterEventHotKey(void *key);
OSStatus GetEventParameter(void *event, unsigned int name, unsigned int type, unsigned int *actualType,
                           unsigned long size, unsigned long *actualSize, void *data);
OSStatus LSRegisterURL(CFRef url, unsigned char update);

extern const CFRef kTISPropertyInputSourceID, kTISPropertyUnicodeKeyLayoutData, kTISPropertyInputSourceType,
    kTISPropertyInputSourceLanguages, kTISTypeKeyboardLayout, kTISNotifySelectedKeyboardInputSourceChanged,
    kLSQuarantineTypeKey;

CFRef CFRetain(CFRef);
void CFRelease(CFRef);
CFIndex CFGetRetainCount(CFRef);
const unsigned char *CFDataGetBytePtr(CFRef);
CFIndex CFDataGetLength(CFRef);
CFIndex CFArrayGetCount(CFRef);
unsigned char CFEqual(CFRef, CFRef);
unsigned char CFStringGetCString(CFRef, char *, CFIndex, unsigned int);

static unsigned short key(const void *layout, unsigned short code, unsigned int modifiers) {
    unsigned short out[4] = {0};
    unsigned long n = 0;
    unsigned int dead = 0;
    if (UCKeyTranslate(layout, code, 0, modifiers, LMGetKbdType(), 1, &dead, 4, &n, out) != 0) return 0xffff;
    return n == 1 ? out[0] : 0;
}

int main(void) {
    CFRef src = TISCopyCurrentKeyboardLayoutInputSource();
    CHECK(src != NULL);
    char id[64];
    CHECK(CFStringGetCString(TISGetInputSourceProperty(src, kTISPropertyInputSourceID), id, sizeof id, 0x08000100));
    CHECK(strcmp(id, "com.apple.keylayout.US") == 0);
    CHECK(CFEqual(TISGetInputSourceProperty(src, kTISPropertyInputSourceType), kTISTypeKeyboardLayout));
    CHECK(CFArrayGetCount(TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages)) == 1);
    CHECK(kTISNotifySelectedKeyboardInputSourceChanged != NULL && kLSQuarantineTypeKey != NULL);
    CFRef other = TISCopyCurrentKeyboardInputSource();
    CHECK(other == src && CFArrayGetCount(TISCreateInputSourceList(NULL, 0)) == 1);
    CFRelease(other);

    CFRef data = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData);
    CHECK(data != NULL && CFDataGetLength(data) > 0);
    const void *layout = CFDataGetBytePtr(data);
    CHECK(key(layout, 0, 0) == 'a');          /* kVK_ANSI_A */
    CHECK(key(layout, 0, 2) == 'A');          /* shift */
    CHECK(key(layout, 0, 4) == 'A');          /* caps lock */
    CHECK(key(layout, 0, 16) == 1);           /* control-A */
    CHECK(key(layout, 18, 0) == '1' && key(layout, 18, 2) == '!');
    CHECK(key(layout, 44, 2) == '?' && key(layout, 50, 2) == '~');
    CHECK(key(layout, 36, 0) == '\r' && key(layout, 49, 0) == ' ' && key(layout, 123, 0) == 0x1c);
    unsigned short out[2];
    unsigned long n = 9;
    unsigned int dead = 0;
    CHECK(UCKeyTranslate(layout, 0, 1, 0, 40, 0, &dead, 2, &n, out) == 0 && n == 0);   /* key up */
    CHECK(UCKeyTranslate("not a layout", 0, 0, 0, 40, 0, &dead, 2, &n, out) == -50);
    CFRelease(src);

    void *handler = NULL, *hotkey = NULL;
    CHECK(GetApplicationEventTarget() != NULL);
    CHECK(InstallEventHandler(GetApplicationEventTarget(), (void *)main, 0, NULL, NULL, &handler) == 0 && handler);
    EventHotKeyID hid = {0x52455831, 7};
    CHECK(RegisterEventHotKey(49, 0x100, hid, GetApplicationEventTarget(), 0, &hotkey) == 0 && hotkey);
    CHECK(GetEventParameter(NULL, 0, 0, NULL, 0, NULL, NULL) == -9870);
    CHECK(UnregisterEventHotKey(hotkey) == 0 && RemoveEventHandler(handler) == 0);
    CHECK(LSRegisterURL(NULL, 1) == 0);
    puts("carbon ok");
    return 0;
}
