// CMediaRemote.c — Pure C query for Now Playing info (same data as Control Center).
// Uses main queue + CFRunLoop pump instead of semaphore (MediaRemote needs main run loop).

#include "CMediaRemote.h"
#include <dlfcn.h>
#include <stdio.h>
#include <dispatch/dispatch.h>
#include <CoreFoundation/CoreFoundation.h>

typedef void (^MRInfoCallback)(CFDictionaryRef);
typedef void (*MRGetInfoFn)(dispatch_queue_t, MRInfoCallback);
typedef void (*MRRegisterFn)(dispatch_queue_t);

static void *g_handle = NULL;
static MRGetInfoFn g_getInfo = NULL;
static bool g_logged_keys = false;

static void ensure_loaded(void) {
    if (g_handle) return;
    g_handle = dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        RTLD_LAZY
    );
    if (!g_handle) { fprintf(stderr, "[CMR] dlopen failed\n"); return; }

    g_getInfo = (MRGetInfoFn)dlsym(g_handle, "MRMediaRemoteGetNowPlayingInfo");
    if (!g_getInfo) { fprintf(stderr, "[CMR] missing MRMediaRemoteGetNowPlayingInfo\n"); return; }

    MRRegisterFn reg = (MRRegisterFn)dlsym(g_handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (reg) reg(dispatch_get_main_queue());

    fprintf(stderr, "[CMR] loaded MediaRemote OK\n");
}

// Log all dictionary keys once so we can see what MediaRemote returns
static void log_dict_keys(CFDictionaryRef dict) {
    if (g_logged_keys || !dict) return;
    g_logged_keys = true;

    CFIndex count = CFDictionaryGetCount(dict);
    fprintf(stderr, "[CMR] now-playing dict has %ld keys:\n", (long)count);

    const void **keys = malloc(sizeof(void*) * count);
    const void **vals = malloc(sizeof(void*) * count);
    CFDictionaryGetKeysAndValues(dict, keys, vals);

    for (CFIndex i = 0; i < count && i < 20; i++) {
        char keyBuf[256] = {0};
        char valBuf[256] = {0};
        if (CFGetTypeID(keys[i]) == CFStringGetTypeID()) {
            CFStringGetCString(keys[i], keyBuf, sizeof(keyBuf), kCFStringEncodingUTF8);
        }
        CFTypeID tid = CFGetTypeID(vals[i]);
        if (tid == CFNumberGetTypeID()) {
            double d = 0;
            CFNumberGetValue(vals[i], kCFNumberFloat64Type, &d);
            snprintf(valBuf, sizeof(valBuf), "%.2f (number)", d);
        } else if (tid == CFStringGetTypeID()) {
            CFStringGetCString(vals[i], valBuf, sizeof(valBuf), kCFStringEncodingUTF8);
        } else if (tid == CFBooleanGetTypeID()) {
            snprintf(valBuf, sizeof(valBuf), "%s (bool)", vals[i] == kCFBooleanTrue ? "true" : "false");
        } else {
            snprintf(valBuf, sizeof(valBuf), "(type %lu)", (unsigned long)tid);
        }
        fprintf(stderr, "[CMR]   %s = %s\n", keyBuf, valBuf);
    }
    free(keys);
    free(vals);
}

double CMediaRemoteGetPlaybackRate(void) {
    ensure_loaded();
    if (!g_getInfo) return -1.0;

    __block double rate = -1.0;
    __block bool done = false;

    // Dispatch to main queue — MediaRemote needs the main run loop
    g_getInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
        done = true;
        log_dict_keys(info);
        if (info) {
            // Try the known key
            CFNumberRef r = CFDictionaryGetValue(
                info, CFSTR("kMRMediaRemoteNowPlayingInfoPlaybackRate")
            );
            if (r) {
                CFNumberGetValue(r, kCFNumberFloat64Type, &rate);
                return;
            }
            // Fallback: scan for any key containing "PlaybackRate" or "playbackRate"
            CFIndex count = CFDictionaryGetCount(info);
            const void **keys = malloc(sizeof(void*) * count);
            const void **vals = malloc(sizeof(void*) * count);
            CFDictionaryGetKeysAndValues(info, keys, vals);
            for (CFIndex i = 0; i < count; i++) {
                if (CFGetTypeID(keys[i]) == CFStringGetTypeID()) {
                    char buf[256] = {0};
                    CFStringGetCString(keys[i], buf, sizeof(buf), kCFStringEncodingUTF8);
                    if (strstr(buf, "laybackRate") || strstr(buf, "layback")) {
                        if (CFGetTypeID(vals[i]) == CFNumberGetTypeID()) {
                            CFNumberGetValue(vals[i], kCFNumberFloat64Type, &rate);
                            fprintf(stderr, "[CMR] found rate under key: %s = %.2f\n", buf, rate);
                        }
                        break;
                    }
                }
            }
            free(keys);
            free(vals);
            if (rate < 0) rate = 0.0; // dict exists but no rate = not playing
        }
    });

    // Pump the main run loop to let the callback fire
    if (!done) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
    }

    if (done && rate >= 0) {
        fprintf(stderr, "[CMR] rate=%.2f\n", rate);
    } else if (!done) {
        fprintf(stderr, "[CMR] callback did not fire\n");
    }

    return done ? rate : -1.0;
}

bool CMediaRemoteIsPlaying(void) {
    return CMediaRemoteGetPlaybackRate() > 0.0;
}
