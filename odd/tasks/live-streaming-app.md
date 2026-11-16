# OnAir v1 — lightweight live-streaming app (StreamYard-simple, runs locally)
Objective: native macOS app that composes camera + screen with one-click layouts and streams to YouTube. Branch: `feat/v1`. Delivery: ask-on-risk. Test runner: `swift test` (Swift Testing).
Plan: `~/.claude/plans/clever-yawning-dongarra.md`.

## Specs
- **S1** Go live on YouTube with one stream key (single destination, RTMPS `rtmps://a.rtmp.youtube.com/live2`). Output layer accepts a list of destinations so multistreaming is additive later (user: multistreaming "Fuera de la v1").
- **S2** Sources: webcam, microphone, screen/window share and macOS system audio (user picked "Pantalla y layouts" and "Audio del sistema").
- **S3** One-click layouts: camera only, screen only, screen + camera picture-in-picture corner, side by side.
- **S4** Rehearsal mode (user: "Ensayo antes de emitir"): live preview of the composed output and layout switching before pressing "Go live".
- **S5** Encoding per YouTube ingest spec: H.264 1080p30, ~6–8 Mbps (configurable), AAC 128 kbps 44.1 kHz stereo, keyframe every 2 s.
- **S6** Live status and errors: connection state, clear message for missing permissions or rejected stream key; clean end of stream.
- Out of scope: remote guests, multistreaming, vertical 9:16, branding/overlays, local recording, Windows/Linux.

## Tasks
| ID | Specs | Route | Status | Commit |
|----|-------|-------|--------|--------|
| T1 | — | inline | pending | |
| T2 | S3, S4, S6 | inline | pending | |
| T3 | S2 | inline | pending | |
| T4 | S3, S4 | inline | pending | |
| T5 | S1, S5 | inline | pending | |
| T6 | S6 | inline | pending | |

- T1 Package skeleton, app bundle script, entitlements/Info.plist.
- T2 Domain: `Layout`, `LayoutGeometry`, `SessionState`, `StreamDestination` (test-first).
- T3 Capture adapters: camera/mic devices; ScreenCaptureKit screen + system audio. (Absorbs plan spikes S-a.)
- T4 Mixer + rehearsal UI: preview, layout buttons. (Absorbs spike S-b.)
- T5 YouTube RTMPS output + Keychain stream key. (Absorbs spike S-c.)
- T6 Live status, errors, end-of-stream cleanup.

## Log
- **L1** (2026-11-13, user, verbatim): "Normalmete para los directos uso streamyard pero es muy caro. por otro lado la gente usa OBS pero es hiper complicado (nunca lo he usado pero es tan complicado que la gente prefiere pagar por Streamyard). Estoy pensando en hacer una version a medio camino, pero no se que requisitos funcinoales necesito ni nada, me gustariaa que me ayudes a planificarlo usando gentle-ai skills"
- **L2** (2026-11-16) Requirements from plan-mode Q&A: features "Multistreaming, Pantalla y layouts"; audience "Primero yo, luego otros"; platforms "YouTube"; multistreaming "Fuera de la v1 (Recomendado)"; extras "Audio del sistema, Ensayo antes de emitir". App name: "me gusta onair".
- **L3** Stack: native Swift + HaishinKit 2.3.0 (Electron rejected: electron/electron#52738 silent system-audio failure with custom picker). Built as a SwiftPM package (no xcodegen installed) + script that assembles the `.app` bundle. No code-signing identity on this Mac: ad-hoc signing, so macOS may re-ask permissions after rebuilds.
- **L4** Deviation from plan: spikes S-a/S-b/S-c are folded into T3–T5 (greenfield, so a throwaway spike costs the same as the real adapter). Stop-and-replan rule still applies if system audio or side-by-side fails.
