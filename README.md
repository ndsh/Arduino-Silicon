<p align="center">
    <img src="http://content.arduino.cc/brand/arduino-color.svg" width="50%" />
</p>

**Important Notice**: This repository is **Arduino Classic** — a community fork of the legacy Arduino IDE 1.x for **macOS on Apple Silicon**, with **Teensyduino** pre-integrated. It is not the official Arduino distribution and is **macOS only** (not Arduino IDE 2.x). For the latest official features and updates, please visit the [Arduino IDE 2.x](https://github.com/arduino/arduino-ide) repository. If you encounter issues related to the newer IDE, please report them there.

Arduino is an open-source physical computing platform based on a simple I/O board and a development environment that implements the Processing/Wiring language. Arduino can be used to develop stand-alone interactive objects or can be connected to software on your computer (e.g. Flash, Processing and MaxMSP). The boards can be assembled by hand or purchased preassembled; the open-source IDE can be downloaded for free at [https://arduino.cc](https://www.arduino.cc/en/Main/Software).

This fork ships **Arduino IDE 1.8.20** (rebranded as **Arduino Classic**) as a native **arm64** `.app` bundle with a bundled JDK 17 and Teensy boards/tools included — no separate Teensyduino installer required. It is based on upstream [Arduino 1.8.19](https://github.com/arduino/Arduino/tree/1.8.19), patched for this distribution.

## Features

- ARM64 app bundle with bundled JDK 17
- Teensy boards and tools pre-installed (no separate Teensyduino installer)
- Native arm64 JNI libraries for serial port listing and code formatting
- Rebranded as **Arduino Classic** to distinguish from upstream Arduino IDE

## More info at

- [Our website](https://www.arduino.cc/)
- [The forums](https://forum.arduino.cc/)
- Follow us on [Twitter](https://twitter.com/arduino)
- And like us at [Facebook](https://www.facebook.com/official.arduino)

## Bug reports and technical discussions

- To report a *bug* in **this fork** or to request *a simple enhancement*, go to [Github Issues](https://github.com/ndsh/Arduino-Silicon/issues) on this repository.
- For bugs in upstream Arduino IDE 1.x (unrelated to Apple Silicon / Teensy integration), see [Arduino Issues](https://github.com/arduino/Arduino/issues).
- More complex requests and technical discussions about Arduino itself should go on the [Arduino Developers mailing list](https://groups.google.com/a/arduino.cc/forum/#!forum/developers).

### Security

If you think you found a vulnerability or other security-related bug in upstream Arduino software, please read the [Arduino security policy](https://github.com/arduino/Arduino/security/policy) and report the bug to their Security Team 🛡️.

e-mail contact: security@arduino.cc

## Installation

This fork targets **macOS on Apple Silicon (arm64)** only. There are no Linux or Windows builds in this repository.

For general Arduino installation guides on other platforms, see:

- [Linux](https://www.arduino.cc/en/Guide/Linux) (see also the [Arduino playground](https://playground.arduino.cc/Learning/Linux))
- [macOS](https://www.arduino.cc/en/Guide/macOS) (official Intel/Universal builds from Arduino)
- [Windows](https://www.arduino.cc/en/Guide/Windows)

## Contents of this repository

This repository contains the Arduino IDE 1.x source tree, adapted for a macOS Apple Silicon release. Unlike upstream, it also vendors **Teensy** hardware packages under `hardware/teensy/`.

The repositories for other Arduino cores and libraries can be found here:

- Non-core specific Libraries are listed under: [Arduino Libraries](https://github.com/arduino-libraries/) (and also a few other places, see `build/build.xml`).
- The AVR core can be found at: [ArduinoCore-avr](https://github.com/arduino/ArduinoCore-avr).
- Teensy cores and tools: [PaulStoffregen/cores](https://github.com/PaulStoffregen/cores), [teensy_loader_cli](https://github.com/PaulStoffregen/teensy_loader_cli).
- Other cores are not included by default but can be installed through the board manager. Their repositories can also be found under [Arduino GitHub organization](https://github.com/arduino/).

## Building and testing

Instructions for building the IDE and running unit tests can be found on the wiki:

- [Building Arduino](https://github.com/arduino/Arduino/wiki/Building-Arduino)
- [Testing Arduino](https://github.com/arduino/Arduino/wiki/Testing-Arduino)

## Credits

Arduino is an open-source project, supported by many. The Arduino team is composed of Massimo Banzi, David Cuartielles, Tom Igoe, and David A. Mellis.

Arduino uses [GNU avr-gcc toolchain](https://gcc.gnu.org/wiki/avr-gcc), [GCC ARM Embedded toolchain](https://launchpad.net/gcc-arm-embedded), [avr-libc](https://www.nongnu.org/avr-libc/), [avrdude](https://www.nongnu.org/avrdude/), [bossac](http://www.shumatech.com/web/products/bossa), [openOCD](http://openocd.org/), and code from [Processing](https://www.processing.org) and [Wiring](http://wiring.org.co).

Teensy support is based on [Teensyduino](https://www.pjrc.com/teensy/td_download.html) by Paul Stoffregen and the PJRC community.

The Apple Silicon macOS build (**Arduino Classic**) is maintained by [Julian Hespenheide](https://www.julian-h.de).

Icon and about image designed by [ToDo](https://www.todo.to.it/).

## License

Same as upstream Arduino IDE — see [license.txt](license.txt).
