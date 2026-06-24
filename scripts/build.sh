#!/usr/bin/env bash
# Build native ARM64 Arduino Classic IDE 1.8.20 + Teensyduino
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR="$REPO_ROOT/vendor"
DIST="$REPO_ROOT/dist"
CACHE="$REPO_ROOT/cache"
BUILD_DIR="$REPO_ROOT/build"
TEENSY_VERSION="${TEENSY_VERSION:-1.61.0}"
TEENSY_TOOLS_VERSION="${TEENSY_TOOLS_VERSION:-1.61.0}"
TEENSY_COMPILE_VERSION="${TEENSY_COMPILE_VERSION:-11.3.1}"
APP_NAME="Arduino Classic"
APP_DISPLAY_NAME="Arduino Classic"
ASSETS="$REPO_ROOT/assets/icons"
APP_ICON_PNG="${APP_ICON_PNG:-$ASSETS/app-icon.png}"
PDE_ICON_PNG="${PDE_ICON_PNG:-$ASSETS/pde-icon.png}"

ANT_VERSION="1.10.15"
ANT_HOME="$CACHE/apache-ant-$ANT_VERSION"

export PATH="/opt/homebrew/bin:$ANT_HOME/bin:$PATH"

step() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing: $1"
}

JDK_HOME="$CACHE/jdk"

setup_java() {
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]]; then
    return 0
  fi
  if command -v /usr/libexec/java_home >/dev/null 2>&1; then
    JAVA_HOME="$(/usr/libexec/java_home -v 17+ 2>/dev/null || /usr/libexec/java_home 2>/dev/null || true)"
  fi
  if [[ -z "${JAVA_HOME:-}" && -d /opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home ]]; then
    JAVA_HOME="/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home"
  fi
  if [[ -z "${JAVA_HOME:-}" && -d /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ]]; then
    JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
  fi
  if [[ -z "${JAVA_HOME:-}" && -d "$JDK_HOME" ]]; then
    normalize_jdk_layout
    local java_bin
    java_bin="$(find "$JDK_HOME" -path '*/Contents/Home/bin/java' -type f 2>/dev/null | head -1)"
    if [[ -n "$java_bin" ]]; then
      JAVA_HOME="$(cd "$(dirname "$java_bin")/.." && pwd)"
    fi
  fi
  if [[ -z "${JAVA_HOME:-}" ]]; then
    bootstrap_jdk
    java_bin="$(find "$JDK_HOME" -path '*/Contents/Home/bin/java' -type f 2>/dev/null | head -1)"
    [[ -n "$java_bin" ]] || die "JDK bootstrap failed"
    JAVA_HOME="$(cd "$(dirname "$java_bin")/.." && pwd)"
  fi
  export JAVA_HOME
  [[ -x "$JAVA_HOME/bin/java" ]] || die "no JDK — install: brew install --cask temurin"
  export PATH="$JAVA_HOME/bin:$PATH"
  step "JAVA_HOME=$JAVA_HOME"
}

bootstrap_jdk() {
  step "bootstrap Temurin JDK 17 (no sudo)"
  mkdir -p "$CACHE"
  local archive="$CACHE/temurin-jdk17-macos-aarch64.tar.gz"
  if [[ ! -f "$archive" ]]; then
    curl -fL --retry 3 -o "$archive" \
      "https://api.adoptium.net/v3/binary/latest/17/ga/mac/aarch64/jdk/hotspot/normal/eclipse?project=jdk"
  fi
  local extract_dir="$CACHE/jdk-extract"
  rm -rf "$extract_dir" "$JDK_HOME"
  mkdir -p "$extract_dir"
  tar -xzf "$archive" -C "$extract_dir"
  local extracted
  extracted="$(find "$extract_dir" -maxdepth 1 -type d -name 'jdk-*' | head -1)"
  [[ -n "$extracted" ]] || die "JDK extract failed"
  mv "$extracted" "$JDK_HOME"
  if [[ ! -d "$JDK_HOME/Contents" && -d "$JDK_HOME"/jdk-*/Contents ]]; then
    inner="$(find "$JDK_HOME" -maxdepth 1 -type d -name 'jdk-*' | head -1)"
    mv "$inner"/* "$JDK_HOME/"
    rmdir "$inner" 2>/dev/null || rm -rf "$inner"
  fi
  rm -rf "$extract_dir"
  normalize_jdk_layout
}

normalize_jdk_layout() {
  if [[ ! -d "$JDK_HOME/Contents/Home" ]]; then
    local inner
    inner="$(find "$JDK_HOME" -maxdepth 1 -type d -name 'jdk-*' | head -1)"
    if [[ -n "$inner" && -d "$inner/Contents" ]]; then
      local tmp="$CACHE/jdk-normalize"
      rm -rf "$tmp"
      mv "$inner" "$tmp"
      rm -rf "$JDK_HOME"
      mv "$tmp" "$JDK_HOME"
    fi
  fi
}

setup_ant() {
  if command -v ant >/dev/null 2>&1; then
    return 0
  fi
  if [[ ! -x "$ANT_HOME/bin/ant" ]]; then
    step "bootstrap Apache Ant $ANT_VERSION"
    mkdir -p "$CACHE"
    local archive="$CACHE/apache-ant-${ANT_VERSION}-bin.tar.gz"
    if [[ ! -f "$archive" ]]; then
      curl -fL --retry 3 -o "$archive" \
        "https://archive.apache.org/dist/ant/binaries/apache-ant-${ANT_VERSION}-bin.tar.gz"
    fi
    rm -rf "$ANT_HOME"
    tar -xzf "$archive" -C "$CACHE"
  fi
  export PATH="$ANT_HOME/bin:$PATH"
  command -v ant >/dev/null 2>&1 || die "ant bootstrap failed"
}

check_deps() {
  mkdir -p "$CACHE" "$VENDOR"
  need_cmd git
  need_cmd zstd
  need_cmd tar
  need_cmd curl
  need_cmd file
  setup_java
  setup_ant
  command -v codesign >/dev/null 2>&1 || true
}

clone_teensy_loader() {
  step "clone teensy_loader_cli"
  if [[ ! -d "$VENDOR/teensy_loader_cli/.git" ]]; then
    git clone --depth 1 https://github.com/PaulStoffregen/teensy_loader_cli.git "$VENDOR/teensy_loader_cli"
  fi
}

download() {
  local url="$1" out="$2" checksum="${3:-}"
  mkdir -p "$(dirname "$out")"
  if [[ -f "$out" ]]; then
    step "cached: $(basename "$out")"
    return 0
  fi
  step "download: $(basename "$out")"
  curl -fL --retry 3 -o "$out" "$url"
  if [[ -n "$checksum" ]]; then
    local expected="${checksum#SHA-256:}"
    local actual
    actual="$(shasum -a 256 "$out" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || die "checksum fail: $(basename "$out")"
  fi
}

extract_zst_tar() {
  local archive="$1" dest="$2"
  mkdir -p "$dest"
  zstd -d -c "$archive" | tar -xf - -C "$dest"
}

download_teensy_packages() {
  local td="td_161"
  download \
    "https://www.pjrc.com/teensy/${td}/teensy-package-${TEENSY_VERSION}.tar.zst" \
    "$CACHE/teensy-package-${TEENSY_VERSION}.tar.zst" \
    "SHA-256:2ef8732bff9e46a52244accf651adcbbf896005f9eba00874d1c7856d43cfe04"
  download \
    "https://www.pjrc.com/teensy/${td}/teensy-tools-${TEENSY_TOOLS_VERSION}-macos.tar.zst" \
    "$CACHE/teensy-tools-${TEENSY_TOOLS_VERSION}-macos.tar.zst" \
    "SHA-256:9fe1b3d6897881e0fcde4ab34eecc343363cd98701c97ba830e3fa785fbae5cc"
  download \
    "https://www.pjrc.com/teensy/td_158/teensy-compile-${TEENSY_COMPILE_VERSION}-macos.tar.zst" \
    "$CACHE/teensy-compile-${TEENSY_COMPILE_VERSION}-macos.tar.zst" \
    "SHA-256:40cfbe36c32fab580738ed870e36b5a85dac44706d19b7c023106f3ad552f7a6"
}

build_macos_native_libs() {
  local app="$1"
  local lib_dir="$app/Contents/Java/lib"
  step "build arm64 liblistSerialsj.dylib"
  local lsp="$VENDOR/listSerialPortsC"
  if [[ ! -d "$lsp/.git" ]]; then
    git clone --depth 1 --recursive https://github.com/arduino/listSerialPortsC.git "$lsp"
  else
    git -C "$lsp" submodule update --init --recursive 2>/dev/null || true
  fi
  (
    cd "$lsp/libserialport"
    ./autogen.sh >/dev/null 2>&1
    CC=clang ./configure --host=aarch64-apple-darwin >/dev/null
    make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 2)" >/dev/null
    cd "$lsp"
    clang -arch arm64 jnilib.c libserialport/macosx.c libserialport/serialport.c \
      -framework IOKit -framework CoreFoundation \
      -Ilibserialport/ -I"$JAVA_HOME/include" -I"$JAVA_HOME/include/darwin" \
      -shared -o "$CACHE/liblistSerialsj-arm64.dylib"
  )
  cp "$CACHE/liblistSerialsj-arm64.dylib" "$lib_dir/liblistSerialsj.dylib"
  chmod 755 "$lib_dir/liblistSerialsj.dylib"

  step "build arm64 libastylej.dylib"
  local astyle_archive="$CACHE/astyle_2.05.1_macosx.tar.gz"
  local astyle_dir="$CACHE/astyle"
  if [[ ! -f "$astyle_archive" ]]; then
    curl -fL --retry 3 -o "$astyle_archive" \
      "https://versaweb.dl.sourceforge.net/project/astyle/astyle/astyle%202.05.1/astyle_2.05.1_macosx.tar.gz" || \
    curl -fL --retry 3 -o "$astyle_archive" \
      "https://sourceforge.net/projects/astyle/files/astyle/astyle%202.05.1/astyle_2.05.1_macosx.tar.gz/download"
  fi
  rm -rf "$astyle_dir"
  tar -xzf "$astyle_archive" -C "$CACHE"
  [[ -d "$astyle_dir/build/mac" ]] || die "AStyle extract failed: $astyle_dir"
  (
    cd "$astyle_dir/build/mac"
    make clean >/dev/null 2>&1 || true
    make java UNIVFLAGS="-arch arm64" \
      JAVAINCS="-I$JAVA_HOME/include -I$JAVA_HOME/include/darwin"
    cp bin/libastyle-2.05.1j.dylib "$CACHE/libastylej-arm64.dylib"
  )
  cp "$CACHE/libastylej-arm64.dylib" "$lib_dir/libastylej.dylib"
  cp "$CACHE/libastylej-arm64.dylib" "$lib_dir/libastylej.jnilib"
  chmod 755 "$lib_dir/libastylej.dylib" "$lib_dir/libastylej.jnilib"
}

fix_jssc_arm64() {
  local app="$1"
  local java_dir="$app/Contents/Java"
  step "upgrade jssc → 2.9.4 (arm64 serial monitor)"
  local jssc_jar="$CACHE/jssc-2.9.4.jar"
  if [[ ! -f "$jssc_jar" ]]; then
    curl -fL --retry 3 -o "$jssc_jar" \
      "https://github.com/java-native/jssc/releases/download/v2.9.4/jssc-2.9.4.jar"
  fi
  find "$java_dir" -maxdepth 1 -name 'jssc-*.jar' -delete
  cp "$jssc_jar" "$java_dir/jssc-2.9.4.jar"
}

png_to_icns() {
  local src="$1" dest="$2"
  local iconset tmpdir
  tmpdir="$(mktemp -d)"
  iconset="$tmpdir/icon.iconset"
  mkdir -p "$iconset"

  sips -z 16 16     "$src" --out "$iconset/icon_16x16.png" >/dev/null
  sips -z 32 32     "$src" --out "$iconset/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$src" --out "$iconset/icon_32x32.png" >/dev/null
  sips -z 64 64     "$src" --out "$iconset/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$src" --out "$iconset/icon_128x128.png" >/dev/null
  sips -z 256 256   "$src" --out "$iconset/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$src" --out "$iconset/icon_256x256.png" >/dev/null
  sips -z 512 512   "$src" --out "$iconset/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$src" --out "$iconset/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$src" --out "$iconset/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$iconset" -o "$dest"
  rm -rf "$tmpdir"
}

generate_macos_icons() {
  local macosx_dir="$BUILD_DIR/macosx"
  [[ -d "$macosx_dir" ]] || return 0

  if [[ ! -f "$APP_ICON_PNG" ]]; then
    step "skip app icon — add $APP_ICON_PNG (square PNG, 1024×1024 recommended)"
    return 0
  fi

  need_cmd sips
  need_cmd iconutil

  step "generate processing.icns from $APP_ICON_PNG"
  png_to_icns "$APP_ICON_PNG" "$macosx_dir/processing.icns"

  if [[ -f "$PDE_ICON_PNG" ]]; then
    step "generate pde.icns from $PDE_ICON_PNG"
    png_to_icns "$PDE_ICON_PNG" "$macosx_dir/pde.icns"
  else
    step "generate pde.icns from $APP_ICON_PNG"
    png_to_icns "$APP_ICON_PNG" "$macosx_dir/pde.icns"
  fi
}

install_bundle_icons() {
  local app="$1"
  local macosx_dir="$BUILD_DIR/macosx"
  local resources="$app/Contents/Resources"
  [[ -f "$macosx_dir/processing.icns" && -d "$resources" ]] || return 0
  step "install bundle icons → $resources"
  cp "$macosx_dir/processing.icns" "$resources/"
  cp "$macosx_dir/pde.icns" "$resources/"
  touch "$app/Contents/Info.plist" "$resources/processing.icns" "$resources/pde.icns"
}

register_app_icon() {
  local app="$1"
  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  [[ -x "$lsregister" ]] || return 0
  step "refresh Finder icon cache"
  "$lsregister" -f "$app" >/dev/null 2>&1 || true
}

patch_app_branding() {
  local app="$1"
  local plist="$app/Contents/Info.plist"
  [[ -f "$plist" ]] || return 0
  step "set app display name → $APP_DISPLAY_NAME"
  plutil -replace CFBundleDisplayName -string "$APP_DISPLAY_NAME" "$plist"
  plutil -replace CFBundleName -string "$APP_DISPLAY_NAME" "$plist"
  sed -i '' \
    -e "s|-Dapple.awt.application.name=Arduino|-Dapple.awt.application.name=${APP_DISPLAY_NAME}|" \
    -e "s|-Xdock:name=Arduino|-Xdock:name=${APP_DISPLAY_NAME}|" \
    -e "s|-Dcom.apple.mrj.application.apple.menu.about.name=Arduino|-Dcom.apple.mrj.application.apple.menu.about.name=${APP_DISPLAY_NAME}|" \
    "$plist"
}

build_arduino() {
  normalize_jdk_layout
  step "ant build Arduino IDE"
  cd "$BUILD_DIR"
  ant clean build -DMACOSX_BUNDLED_JVM="$JAVA_HOME"
}

find_app() {
  local candidates=(
    "$BUILD_DIR/macosx/work/Arduino.app"
    "$BUILD_DIR/macosx/dist/Arduino.app"
  )
  for c in "${candidates[@]}"; do
    if [[ -d "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  find "$BUILD_DIR" -name "Arduino.app" -type d 2>/dev/null | head -1
}

bundle_jdk() {
  local app="$1"
  local jdk_dest="$app/Contents/Java/jdk"
  step "bundle ARM64 JDK → Contents/Java/jdk"

  [[ -x "$JAVA_HOME/bin/java" ]] || die "no JDK to bundle"

  rm -rf "$jdk_dest" "$app/Contents/PlugIns/jdk"
  mkdir -p "$jdk_dest"
  cp -R "$JAVA_HOME/." "$jdk_dest/"

  local launcher="$app/Contents/MacOS/Arduino"
  if [[ -f "$launcher" ]]; then
    cat > "$launcher" <<LAUNCHER
#!/bin/bash
APP_ROOT="\$(cd "\$(dirname "\$0")/.." && pwd)"
JAVA_DIR="\$APP_ROOT/Java"
export JAVA_HOME="\$APP_ROOT/Java/jdk"
export PATH="\$JAVA_HOME/bin:\$PATH"

CLASSPATH=""
while IFS= read -r jar; do
  [[ -n "\$CLASSPATH" ]] && CLASSPATH+=":"
  CLASSPATH+="\$jar"
done < <(find "\$JAVA_DIR" -name '*.jar' | sort)

exec "\$JAVA_HOME/bin/java" \
  --add-exports java.desktop/com.apple.eio=ALL-UNNAMED \
  --add-exports java.desktop/com.apple.eawt=ALL-UNNAMED \
  -Dapple.laf.useScreenMenuBar=true \
  "-Dapple.awt.application.name=${APP_DISPLAY_NAME}" \
  -Dcom.apple.macos.use-file-dialog-packages=true \
  -Dcom.apple.smallTabs=true \
  -DAPP_DIR="\$JAVA_DIR" \
  -Djava.net.preferIPv4Stack=true \
  "-Xdock:name=${APP_DISPLAY_NAME}" \
  "-Xdock:icon=\$APP_ROOT/Resources/processing.icns" \
  "-Dcom.apple.mrj.application.apple.menu.about.name=${APP_DISPLAY_NAME}" \
  -Dfile.encoding=UTF-8 \
  -Xms128M \
  -Xmx512M \
  -splash:"\$JAVA_DIR/lib/splash.png" \
  -cp "\$CLASSPATH" \
  processing.app.Base "\$@"
LAUNCHER
    chmod +x "$launcher"
  fi
}

fix_macos_jars() {
  local app="$1"
  local apple_src="$REPO_ROOT/app/lib/apple.jar"
  local apple_dst="$app/Contents/Java/apple.jar"
  [[ -f "$apple_src" ]] || return 0
  step "install macOS apple.jar (AppEvent API)"
  cp "$apple_src" "$apple_dst"
}

integrate_teensy() {
  local app="$1"
  local hw="$app/Contents/Java/hardware/teensy/avr"
  local tools="$app/Contents/Java/hardware/teensy/tools"
  step "integrate Teensy $TEENSY_VERSION → $hw"

  local staging="$CACHE/teensy-staging"
  rm -rf "$staging"
  mkdir -p "$staging"

  extract_zst_tar "$CACHE/teensy-package-${TEENSY_VERSION}.tar.zst" "$staging/package"
  extract_zst_tar "$CACHE/teensy-tools-${TEENSY_TOOLS_VERSION}-macos.tar.zst" "$staging/tools"
  extract_zst_tar "$CACHE/teensy-compile-${TEENSY_COMPILE_VERSION}-macos.tar.zst" "$staging/compile"

  rm -rf "$(dirname "$hw")"
  mkdir -p "$hw" "$tools"

  local pkg_root
  pkg_root="$(find "$staging/package" -path '*/hardware/avr/*' -name boards.txt -print -quit | xargs dirname 2>/dev/null || true)"
  [[ -n "$pkg_root" && -f "$pkg_root/boards.txt" ]] || \
    pkg_root="$(find "$staging/package" -name boards.txt -print -quit | xargs dirname)"
  [[ -f "$pkg_root/boards.txt" ]] || die "Teensy boards.txt not found in package"
  cp -R "$pkg_root/." "$hw/"

  local teensy_bin
  teensy_bin="$(find "$staging/tools" -type f -name teensy_ports -print -quit | xargs dirname 2>/dev/null || true)"
  [[ -n "$teensy_bin" ]] || teensy_bin="$staging/tools/tools"
  if [[ -d "$teensy_bin" ]]; then
    cp -R "$teensy_bin/." "$tools/"
  fi

  if [[ -d "$staging/compile/tools" ]]; then
    cp -R "$staging/compile/tools/." "$tools/"
  fi

  chmod +x "$tools"/* 2>/dev/null || true
  find "$tools" -type f \( -name teensy_* -o -name precompile_helper -o -name stdout_redirect -o -name mktinyfat -o -name vscode_plugins \) -exec chmod +x {} + 2>/dev/null || true

  cat > "$hw/platform.local.txt" <<'PLATFORM_LOCAL'
# Teensyduino installer layout for portable ARM64 build
compiler.path={runtime.hardware.path}/tools/
teensytools.path={runtime.hardware.path}/tools/
discovery.teensy.pattern="{runtime.hardware.path}/tools/teensy_ports" -J2
tools.teensyloader.cmd.path={runtime.hardware.path}/tools
PLATFORM_LOCAL

  mkdir -p "$hw/lib"
  echo "$TEENSY_VERSION" > "$hw/lib/version.txt"
}

ensure_pjrc_arm_toolchain_cache() {
  local cache_arm="$CACHE/pjrc-arm-toolchain"
  [[ -d "$cache_arm/bin" ]] && return 0

  local archive="$CACHE/teensy-compile-${TEENSY_COMPILE_VERSION}-macos.tar.zst"
  [[ -f "$archive" ]] || die "missing Teensy compile package: $archive"

  step "extract PJRC arm-none-eabi GCC 11.3.1 to cache"
  local tmp="$CACHE/teensy-compile-extract"
  rm -rf "$tmp" "$cache_arm"
  mkdir -p "$tmp" "$cache_arm"
  extract_zst_tar "$archive" "$tmp"
  local src
  src="$(find "$tmp" -type d -path '*/tools/arm' -print -quit)"
  [[ -d "$src/bin" ]] || die "PJRC arm toolchain not found in compile package"
  cp -R "$src/." "$cache_arm/"
  rm -rf "$tmp"
}

install_brew_arm_toolchain() {
  local arm_dir="$1"
  local brew_gcc="/opt/homebrew/opt/arm-none-eabi-gcc"
  local brew_bin="/opt/homebrew/opt/arm-none-eabi-binutils"
  if [[ ! -d "$brew_gcc" || ! -d "$brew_bin" ]]; then
    step "WARN: skip brew arm toolchain — install arm-none-eabi-gcc arm-none-eabi-binutils"
    return 1
  fi

  local gcc_ver
  gcc_ver="$(basename "$(find "$brew_gcc/lib/gcc/arm-none-eabi" -mindepth 1 -maxdepth 1 -type d | head -1)")"
  [[ -n "$gcc_ver" ]] || die "cannot detect arm-none-eabi-gcc version in $brew_gcc"

  step "install Homebrew ARM64 arm-none-eabi GCC $gcc_ver (experimental; may break some libraries)"
  rm -rf "$arm_dir/bin" "$arm_dir/libexec" "$arm_dir/lib/gcc"
  mkdir -p "$arm_dir/lib/gcc/arm-none-eabi"
  cp -R "$brew_gcc/bin" "$arm_dir/"
  cp -R "$brew_gcc/libexec" "$arm_dir/"
  cp -R "$brew_gcc/lib/gcc/arm-none-eabi/$gcc_ver" "$arm_dir/lib/gcc/arm-none-eabi/"
  cp "$brew_bin/bin/"* "$arm_dir/bin/"

  local cxx_inc="$arm_dir/arm-none-eabi/include/c++"
  if [[ -d "$cxx_inc" && ! -e "$cxx_inc/$gcc_ver" ]]; then
    local cxx_ver
    cxx_ver="$(basename "$(find "$cxx_inc" -mindepth 1 -maxdepth 1 -type d | head -1)")"
    [[ -n "$cxx_ver" ]] && ln -sfn "$cxx_ver" "$cxx_inc/$gcc_ver"
  fi

  chmod -R u+w "$arm_dir/bin" "$arm_dir/libexec" "$arm_dir/lib/gcc" 2>/dev/null || true
  find "$arm_dir/bin" "$arm_dir/libexec" -type f -perm +111 -exec chmod +x {} + 2>/dev/null || true
  return 0
}

install_native_arm_toolchain() {
  local app="$1"
  local arm_dir="$app/Contents/Java/hardware/teensy/tools/arm"
  [[ -d "$(dirname "$arm_dir")" ]] || return 0

  if [[ "${USE_NATIVE_ARM_GCC:-0}" == "1" ]]; then
    if install_brew_arm_toolchain "$arm_dir"; then
      return 0
    fi
    step "WARN: brew arm toolchain unavailable — falling back to PJRC GCC 11.3.1"
  fi

  step "install PJRC arm-none-eabi GCC 11.3.1 (Teensyduino-tested; x86_64 on macOS)"
  ensure_pjrc_arm_toolchain_cache
  rm -rf "$arm_dir"
  mkdir -p "$(dirname "$arm_dir")"
  cp -R "$CACHE/pjrc-arm-toolchain/." "$arm_dir/"
  find "$arm_dir" -type l -name '16.1.0' -delete 2>/dev/null || true
  chmod -R u+w "$arm_dir" 2>/dev/null || true
  find "$arm_dir" -type f -perm +111 -exec chmod +x {} + 2>/dev/null || true

  if [[ "$(uname -m)" == "arm64" ]] && file "$arm_dir/bin/arm-none-eabi-g++" | grep -q x86_64; then
    step "NOTE: Teensy compiles use x86_64 GCC — install Rosetta: softwareupdate --install-rosetta"
  fi
}

build_native_teensy_loader() {
  local app="$1"
  step "build native teensy_loader_cli (IOKit)"
  make -C "$VENDOR/teensy_loader_cli" clean
  make -C "$VENDOR/teensy_loader_cli" OS=MACOSX

  local loader="$VENDOR/teensy_loader_cli/teensy_loader_cli"
  [[ -x "$loader" ]] || die "teensy_loader_cli build failed"

  local arch
  arch="$(file "$loader" | grep -o 'arm64\|x86_64' | head -1)"
  step "teensy_loader_cli arch: $arch"

  find "$app" -name 'teensy_loader_cli' -type f 2>/dev/null | while read -r old; do
    cp "$loader" "$old"
    chmod +x "$old"
  done
}

replace_x86_tools() {
  local app="$1"
  step "scan + replace x86_64 binaries"

  local brew_prefix="/opt/homebrew"
  local replacements=0

  while IFS= read -r -d '' f; do
    if file "$f" | grep -q 'x86_64'; then
      local base
      base="$(basename "$f")"
      local native=""
      case "$base" in
        avr-gcc|avr-g++) native="$brew_prefix/bin/$base" ;;
        avr-objcopy|avr-objdump|avr-size) native="$brew_prefix/bin/$base" ;;
        avrdude) native="$brew_prefix/bin/avrdude" ;;
        teensy_loader_cli) continue ;;
      esac
      if [[ -n "$native" && -x "$native" ]]; then
        local narch
        narch="$(file "$native" | grep -o 'arm64' || true)"
        if [[ "$narch" == "arm64" ]]; then
          step "replace $base"
          cp "$native" "$f"
          chmod +x "$f"
          replacements=$((replacements + 1))
        fi
      fi
    fi
  done < <(find "$app" -type f -perm +111 -print0 2>/dev/null)

  step "replaced $replacements tool binaries"
}

patch_preferences() {
  local app="$1"
  local prefs="$app/Contents/Java/lib/preferences.txt"
  [[ -f "$prefs" ]] || return 0
  step "disable network update checks"
  if ! grep -q 'update.check' "$prefs" 2>/dev/null; then
    cat >> "$prefs" <<'PREFS'

# custom build — skip network checks
update.check=false
update.check.interval=0
PREFS
  fi
}

verify_arm64() {
  local app="$1"
  step "verify ARM64"
  local x86_count=0
  while IFS= read -r -d '' f; do
    if file "$f" | grep -q 'x86_64'; then
      echo "  x86: $f"
      x86_count=$((x86_count + 1))
    fi
  done < <(find "$app" -type f -perm +111 -print0 2>/dev/null)
  if [[ $x86_count -gt 0 ]]; then
    step "WARN: $x86_count x86_64 binaries remain (may need Rosetta)"
  else
    step "all executables ARM64 native"
  fi
}

package_app() {
  local app="$1"
  mkdir -p "$DIST"
  rm -rf "$DIST/$APP_NAME.app"
  cp -R "$app" "$DIST/$APP_NAME.app"
  step "output: $DIST/$APP_NAME.app"
}

main() {
  check_deps
  mkdir -p "$DIST" "$ASSETS"

  clone_teensy_loader
  download_teensy_packages
  generate_macos_icons
  build_arduino

  local app
  app="$(find_app)"
  [[ -d "$app" ]] || die "Arduino.app not found after build"

  install_bundle_icons "$app"
  bundle_jdk "$app"
  patch_app_branding "$app"
  fix_macos_jars "$app"
  build_macos_native_libs "$app"
  fix_jssc_arm64 "$app"
  integrate_teensy "$app"
  install_native_arm_toolchain "$app"
  build_native_teensy_loader "$app"
  replace_x86_tools "$app"
  patch_preferences "$app"
  verify_arm64 "$app"
  package_app "$app"
  register_app_icon "$DIST/$APP_NAME.app"

  step "done — open $DIST/$APP_NAME.app"
}

main "$@"
