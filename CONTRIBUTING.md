# Contributing

Issues and pull requests are welcome.

Before opening a pull request:

1. Build with `./build.sh` on macOS 13 or newer.
2. Confirm `codesign --verify --deep --strict "build/DJI Mic 2 Bridge.app"` passes.
3. Test connect, disconnect, low-latency keep-alive, and default-input selection.
4. Do not include serial numbers, Bluetooth addresses, recordings, signing keys,
   provisioning profiles, or other private data.

Compatibility reports should include the macOS version, Mac model, transmitter
firmware version, and the exact UI error. Please keep the change focused and
explain any power, privacy, or backward-compatibility tradeoffs.
