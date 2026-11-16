# OnAir

Lightweight macOS live-streaming app: camera + screen, one-click layouts, straight to YouTube.

[Website](https://onair.goyocancio.es/) · [Report a problem](https://github.com/McGregory99/onair/issues/new)

- **Sources:** camera, microphone, a screen or a single window, and the Mac's system audio.
- **Layouts:** Camera, Screen, Screen + camera, Side by side — one click, also while live.
- **Rehearsal:** a live preview of exactly what YouTube will get, before you go live.
- **Output:** YouTube over RTMPS with your stream key, 1080p H.264 at 4.5, 6 or 8 Mbps.

Not yet: remote guests, several platforms at once, overlays, vertical video, local recording.

## Build it

Needs macOS 14 or later and Xcode 16 or later (Swift 6).

```sh
git clone https://github.com/McGregory99/onair.git
cd onair
scripts/build-app.sh
open build/OnAir.app
```

The app is signed ad hoc, so macOS may ask again for camera, microphone and screen recording
permission after each rebuild. To sign with your own identity, set `ONAIR_SIGN_IDENTITY`.

Run the tests with `swift test`.
