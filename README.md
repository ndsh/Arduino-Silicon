# Arduino Classic for Apple Silicon

A native macOS build of **Arduino IDE 1.8.20** (Arduino Classic) with **Teensyduino** integration, targeting Apple Silicon (arm64).

This fork is based on the upstream [Arduino 1.8.19](https://github.com/arduino/Arduino/tree/1.8.19) codebase, patched to **1.8.20** for this distribution. It is **not** Arduino IDE 2.x and builds **macOS only**.

## Features

- ARM64 app bundle with bundled JDK 17
- Teensy boards and tools pre-installed (no separate Teensyduino installer)
- Native arm64 JNI libraries for serial port listing and code formatting
- Rebranded as **Arduino Classic** to distinguish from upstream Arduino IDE

## Build

See [docs/BUILDING.md](docs/BUILDING.md) for prerequisites and instructions.

```bash
./scripts/build.sh
open "dist/Arduino Classic.app"
```

## Roadmap

Pure-native toolchains (zero x86_64 binaries, no Rosetta) are tracked in [docs/SILICON_ROADMAP.md](docs/SILICON_ROADMAP.md).

## License

Same as upstream Arduino IDE — see [license.txt](license.txt).
