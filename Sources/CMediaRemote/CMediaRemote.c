// CMediaRemote.c
//
// Pure C wrapper for MediaRemote's MRMediaRemoteGetNowPlayingInfo.
// Uses native C blocks — no Swift @convention(block) or AnyObject casting.
// Same API the Touch Bar / Control Center use to detect media playback.

#include "CMediaRemote.h"
#include <dlfcn.h>
#include <dispatch/dispatch.h>
#include <CoreFoundation/CoreFoundation.h>

typedef void (^MRInfoCallback)(CFDictionaryRef);
typedef void (*MRGetInfoFn)(dispatch_queue_t, MRInfoCallback);
typedef void (*MRRegisterFn)(dispatch_queue_t);

static void *g_handle = NULL;
static MRGetInfoFn g_getInfo = NULL;

static void ensure_loaded(void) {
    if (g_handle) return;
    g_handle = dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        RTLD_LAZY
    );
    if (!g_handle) return;

    g_getInfo = (MRGetInfoFn)dlsym(g_handle, "MRMediaRemoteGetNowPlayingInfo");

    // Register for now-playing notifications so the framework starts tracking
    MRRegisterFn reg = (MRRegisterFn)dlsym(g_handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (reg) {
        reg(dispatch_get_main_queue());
    }
}

double CMediaRemoteGetPlaybackRate(void) {
    ensure_loaded();
    if (!g_getInfo) return -1.0;

    __block double rate = -1.0;
    __block bool got_result = false;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    g_getInfo(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0),
        ^(CFDictionaryRef info) {
            got_result = true;
            if (info) {
                CFNumberRef r = CFDictionaryGetValue(
                    info, CFSTR("kMRMediaRemoteNowPlayingInfoPlaybackRate")
                );
                if (r) {
                    CFNumberGetValue(r, kCFNumberFloat64Type, &rate);
                } else {
                    rate = 0.0;
                }
            }
            dispatch_semaphore_signal(sem);
        }
    );

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC));
    return got_result ? rate : -1.0;
}

bool CMediaRemoteIsPlaying(void) {
    return CMediaRemoteGetPlaybackRate() > 0.0;
}
