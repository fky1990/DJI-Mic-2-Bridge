# Changelog

All notable changes to this project are documented here.

## [0.2.1] - 2026-07-30

- Preserve the user's default output and system-output devices when connecting.
- Immediately restore the previous speaker if macOS switches output to DJI Mic 2.
- Remember later manual speaker changes without changing the selected input.

## [0.2.0] - 2026-07-24

- Add a continuous Core Audio keep-alive to reduce HFP/SCO wake latency.
- Add a distinct microphone + D menu bar icon.
- Add microphone permission disclosure and low-latency status reporting.
- Build a universal Apple Silicon and Intel application.

## [0.1.0] - 2026-07-24

- Establish an HFP Audio Gateway and SCO link with a paired DJI Mic 2.
- Expose the transmitter as a Core Audio input.
- Add menu bar controls for reconnect, disconnect, and default input selection.
