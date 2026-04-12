#ifndef CMediaRemote_h
#define CMediaRemote_h

#include <stdbool.h>

/// Query MediaRemote for current playback rate.
/// Returns >0 if playing, 0 if paused, -1 if query failed.
/// Synchronous — blocks up to 200ms. Native C blocks, no Swift interop issues.
double CMediaRemoteGetPlaybackRate(void);

/// Convenience: returns true if playback rate > 0.
bool CMediaRemoteIsPlaying(void);

#endif
