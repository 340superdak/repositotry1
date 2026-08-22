#!/bin/bash
#
# Build PAPPL and LPrint (with the ZP 450 driver entries) and install them
# under $PREFIX. Run via install.sh, or directly to rebuild after changing the
# pinned versions or the patch.
#

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$HERE/common.sh"

PATCH_FILE="$HERE/../patches/0001-add-zebra-zp450-driver-entries.patch"

PAPPL_TARBALL="pappl-${PAPPL_VERSION}.tar.gz"
LPRINT_TARBALL="lprint-${LPRINT_VERSION}.tar.gz"
PAPPL_URL="https://github.com/michaelrsweet/pappl/releases/download/v${PAPPL_VERSION}/${PAPPL_TARBALL}"
LPRINT_URL="https://github.com/michaelrsweet/lprint/releases/download/v${LPRINT_VERSION}/${LPRINT_TARBALL}"

# Checksums for the pinned versions. Update these together with the versions in
# common.sh; an empty value skips verification.
PAPPL_SHA256="${PAPPL_SHA256:-50fec863a28a3c39af639de29d58bf8cefdafa258b66e3c0dfbe2097801dc9db}"
LPRINT_SHA256="${LPRINT_SHA256:-f0a7f8d84b529db000e2ba23fdd30980d0ef50c26b8ef780b36bfdf18cd67ba5}"

# CUPS: macOS ships 2.3.x, but LPrint requires 2.4 or later. Homebrew's cups is
# keg-only, so it does not shadow the system one; we point pkg-config at it and
# build BOTH PAPPL and LPrint against it. PAPPL accepts 2.2+ and would happily
# use Apple's, but then the printer application would hold two different libcups
# in one process.
BREW_PACKAGES=(pkg-config libusb libpng jpeg-turbo openssl@3 cups)

install_dependencies() {
  info "Checking build dependencies"

  if ! xcode-select -p >/dev/null 2>&1; then
    die "Xcode command line tools are missing. Install them with: xcode-select --install"
  fi
  ok "Xcode command line tools: $(xcode-select -p)"

  if ! command -v brew >/dev/null 2>&1; then
    die "Homebrew is required to supply libusb/libpng/openssl. Install it from https://brew.sh"
  fi

  local missing=()
  local pkg
  for pkg in "${BREW_PACKAGES[@]}"; do
    if brew list --formula "$pkg" >/dev/null 2>&1; then
      ok "$pkg"
    else
      missing+=("$pkg")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    info "Installing: ${missing[*]}"
    brew install "${missing[@]}"
  fi
}

# Refuse to build cross-architecture. Mixing an x86_64 toolchain (a Rosetta
# shell, or Intel Homebrew under /usr/local) with arm64 libraries makes the
# linker ignore the mismatched files and report every symbol in them as
# missing - "ld: symbol(s) not found for architecture x86_64" - which looks
# nothing like the actual problem.
check_architecture() {
  local shell_arch native brew_prefix
  shell_arch="$(uname -m)"
  native="$(native_arch)"

  if [ "$shell_arch" != "$native" ]; then
    error "Building as $shell_arch on an $native Mac cannot link against $native libraries."
    error "install.sh re-runs itself under 'arch -$native' to avoid this; running"
    error "build.sh directly skips that. Either use ./install.sh, or start a"
    error "native shell with: arch -$native zsh"
    die "Refusing to build cross-architecture."
  fi

  brew_prefix="$(brew --prefix)"
  if [ "$native" = "arm64" ] && [ "$brew_prefix" = "/usr/local" ]; then
    error "Homebrew at /usr/local is the Intel build; on Apple Silicon it supplies x86_64 libraries."
    error "Install the native Homebrew (it lives at /opt/homebrew) and re-run, or"
    error "point PATH at an arm64 brew before running install.sh."
    die "Refusing to build against a mismatched Homebrew."
  fi

  ok "architecture: $native, Homebrew at $brew_prefix"
}

setup_build_env() {
  local brew_prefix
  brew_prefix="$(brew --prefix)"

  # PAPPL needs OpenSSL for TLS and libusb for USB devices; Homebrew keeps
  # openssl@3 keg-only, so its .pc files have to be added explicitly.
  export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${brew_prefix}/opt/cups/lib/pkgconfig:${brew_prefix}/lib/pkgconfig:${brew_prefix}/opt/openssl@3/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
  export CPPFLAGS="-I${brew_prefix}/include ${CPPFLAGS:-}"
  export LDFLAGS="-L${brew_prefix}/lib ${LDFLAGS:-}"

  # Build for whatever architecture this Mac actually is; a universal binary
  # would only matter for redistribution, which this install does not do.
  info "Building for $(uname -m) against Homebrew at ${brew_prefix}"
}

# check_cups  - LPrint requires CUPS 2.4+; macOS ships 2.3.x. Verify before
# building anything, so the failure does not land after PAPPL is installed.
check_cups() {
  local ver major minor rest

  if ! ver="$(pkg-config --modversion cups 2>/dev/null)" || [ -z "$ver" ]; then
    error "pkg-config cannot find a CUPS development package."
    error "macOS's own CUPS is 2.3.x and has no .pc file; LPrint needs 2.4+."
    die "Install Homebrew's CUPS with: brew install cups"
  fi

  major="${ver%%.*}"
  rest="${ver#*.}"
  minor="${rest%%.*}"

  if [ "$major" -lt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -lt 4 ]; }; then
    error "pkg-config reports CUPS $ver, but LPrint requires 2.4 or later."
    error "macOS ships 2.3.x; Homebrew's keg-only cups provides a newer one."
    die "Install it with: brew install cups"
  fi

  ok "CUPS $ver (via pkg-config)"
}

# force_native_arch  - run in a configured source tree, before make.
#
# PAPPL and LPrint both add "-arch x86_64 -arch arm64" on macOS 11+ to produce
# universal binaries. Homebrew ships single-architecture libraries, so the
# foreign slice has nothing to link against and the build dies with
# "ignoring file ... found architecture 'arm64', required architecture
# 'x86_64'" followed by undefined symbols for a slice nobody wanted.
# PAPPL skips its flags when -arch is already set; LPrint appends regardless.
# Rewriting Makedefs after configure handles both the same way.
force_native_arch() {
  local arch other f found=0
  arch="$(native_arch)"
  if [ "$arch" = "arm64" ]; then other="x86_64"; else other="arm64"; fi

  # PAPPL keeps its flags in Makedefs; LPrint has no Makedefs and keeps them in
  # Makefile. Rewrite whichever exist, and treat "neither exists" as an error -
  # silently doing nothing here produces a universal build that fails to link
  # much later, which is how this was missed the first time.
  for f in Makedefs Makefile; do
    [ -f "$f" ] || continue
    found=1

    sed -i '' \
      -e "s/-arch $other -arch $arch/-arch $arch/g" \
      -e "s/-arch $arch -arch $other/-arch $arch/g" \
      -e "s/-arch $other/-arch $arch/g" \
      "$f"

    if grep -q -- "-arch $other" "$f"; then
      die "Could not remove -arch $other from $f; the build would fail to link."
    fi
  done

  if [ "$found" != "1" ]; then
    die "No Makedefs or Makefile in $(pwd) - cannot force a native build."
  fi

  ok "building for $arch only (universal build flags removed)"
}

# resign_local  - PAPPL and LPrint both codesign with "-o runtime" (hardened
# runtime) using the ad-hoc identity "-". Hardened runtime enables library
# validation, which requires every loaded dylib to carry the same Team ID as
# the process. Two separately ad-hoc-signed artifacts each have no Team ID, and
# macOS treats that as a mismatch:
#
#   Library not loaded: /usr/local/lib/libpappl.1.dylib
#   Reason: ... mapping process and mapped file (non-platform) have different
#   Team IDs
#
# Re-signing ad-hoc without hardened runtime drops library validation. This is
# fine for locally built software; a redistributable build would instead sign
# everything with one Developer ID.
resign_local() {
  local f
  info "Re-signing installed binaries for local use"

  local ents
  ents="$(mktemp "${TMPDIR:-/tmp}/zp450-ents.XXXXXX")"
  cat >"$ents" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
</dict>
</plist>
PLIST

  # Libraries first: re-signing them after the executable would not invalidate
  # anything here, but keeping the order stable makes failures easier to read.
  for f in "${PREFIX}"/lib/libpappl*.dylib; do
    [ -e "$f" ] || continue
    if ! run_root codesign --force --sign - --timestamp=none "$f" >/dev/null 2>&1; then
      die "codesign failed for $f"
    fi
    ok "signed $(basename "$f")"
  done

  # The executable also gets the entitlement, so library validation stays off
  # even if a future toolchain re-applies hardened runtime.
  if ! run_root codesign --force --sign - --timestamp=none --entitlements "$ents" "$LPRINT" >/dev/null 2>&1; then
    rm -f "$ents"
    die "codesign failed for $LPRINT"
  fi
  rm -f "$ents"
  ok "signed $(basename "$LPRINT")"

  if codesign -d --verbose=2 "$LPRINT" 2>&1 | grep -q 'flags=.*runtime'; then
    warn "hardened runtime still set on $LPRINT; relying on the"
    warn "disable-library-validation entitlement instead."
  fi
}

# smoke_test  - the previous run installed binaries that could not load their
# own library, and the driver check reported it as a missing driver. Actually
# run the thing before declaring the build good.
smoke_test() {
  info "Checking that lprint runs"
  if ! "$LPRINT" drivers >/dev/null 2>&1; then
    error "$LPRINT installed but cannot run. Full error:"
    "$LPRINT" drivers 2>&1 | head -10 >&2
    die "LPrint cannot load its libraries."
  fi
  ok "lprint runs and loads libpappl"
}

# verify_binary_arch FILE  - a universal or foreign binary here means a flag
# was missed; catch it at the source rather than at link time in the next
# project, or at runtime.
verify_binary_arch() {
  local f="$1" arch archs
  arch="$(native_arch)"
  archs="$(file -b "$f" 2>/dev/null || true)"

  case "$archs" in
    *"$arch"*) ok "$(basename "$f"): $arch" ;;
    *) die "$(basename "$f") is not $arch: $archs" ;;
  esac
}

# fetch_and_verify URL TARBALL SHA256
fetch_and_verify() {
  local url="$1" tarball="$2" sha="$3"

  if [ ! -f "$tarball" ]; then
    info "Downloading $tarball"
    curl -fsSL -o "$tarball.part" "$url"
    mv "$tarball.part" "$tarball"
  else
    info "Using cached $tarball"
  fi

  if [ -n "$sha" ]; then
    local actual
    actual="$(shasum -a 256 "$tarball" | awk '{print $1}')"
    if [ "$actual" != "$sha" ]; then
      rm -f "$tarball"
      die "Checksum mismatch for $tarball (expected $sha, got $actual). Download removed."
    fi
    ok "checksum verified"
  fi
}

build_pappl() {
  info "Building PAPPL ${PAPPL_VERSION}"
  fetch_and_verify "$PAPPL_URL" "$PAPPL_TARBALL" "$PAPPL_SHA256"

  rm -rf "pappl-${PAPPL_VERSION}"
  tar xzf "$PAPPL_TARBALL"
  (
    cd "pappl-${PAPPL_VERSION}" || exit 1
    # Tee to a log: a link failure scrolls past fast, and the lines above the
    # final "clang: error" are the ones that name the cause.
    ./configure --prefix="$PREFIX" --with-tls=openssl --enable-libusb --disable-static 2>&1 | tee "$BUILD_DIR/pappl-configure.log"
    force_native_arch
    make -j"$(sysctl -n hw.ncpu)" 2>&1 | tee "$BUILD_DIR/pappl-build.log"
    run_root make install
  )
  if [ ! -f "${PREFIX}/lib/libpappl.1.dylib" ] && [ ! -f "${PREFIX}/lib/libpappl.dylib" ]; then
    die "PAPPL did not install a library into ${PREFIX}/lib - see $BUILD_DIR/pappl-build.log"
  fi
  verify_binary_arch "$(ls "${PREFIX}"/lib/libpappl*.dylib | head -1)"
  ok "PAPPL installed to $PREFIX"
}

build_lprint() {
  info "Building LPrint ${LPRINT_VERSION} with ZP 450 driver entries"
  fetch_and_verify "$LPRINT_URL" "$LPRINT_TARBALL" "$LPRINT_SHA256"

  rm -rf "lprint-${LPRINT_VERSION}"
  tar xzf "$LPRINT_TARBALL"
  (
    cd "lprint-${LPRINT_VERSION}" || exit 1

    if patch -p1 --dry-run <"$PATCH_FILE" >/dev/null 2>&1; then
      patch -p1 <"$PATCH_FILE"
      ok "ZP 450 driver entries applied"
    else
      warn "ZP 450 patch did not apply to LPrint ${LPRINT_VERSION} - building unmodified."
      warn "The generic driver ${DRIVER_FALLBACK} will be used instead."
    fi

    ./configure --prefix="$PREFIX" 2>&1 | tee "$BUILD_DIR/lprint-configure.log"
    force_native_arch
    make -j"$(sysctl -n hw.ncpu)" 2>&1 | tee "$BUILD_DIR/lprint-build.log"
    run_root make install
  )
  [ -x "$LPRINT" ] || die "LPrint did not install to $LPRINT - see $BUILD_DIR/lprint-build.log"
  verify_binary_arch "$LPRINT"
  ok "LPrint installed to $PREFIX"
}

main() {
  # install.sh --skip-build reuses installed binaries but still needs the
  # signature repair, which is why a broken install could survive a re-run.
  if [ "${1:-}" = "--resign-only" ]; then
    resign_local
    smoke_test
    return 0
  fi

  check_architecture
  install_dependencies
  setup_build_env
  check_cups

  local stamp="$BUILD_DIR/.build-arch"
  if [ -f "$stamp" ] && [ "$(cat "$stamp")" != "$(uname -m)" ]; then
    warn "Build tree holds $(cat "$stamp") objects but this is $(uname -m) - removing it."
    warn "(Stale objects would relink and fail the same way.)"
    rm -rf "$BUILD_DIR"
  fi

  mkdir -p "$BUILD_DIR"
  uname -m >"$stamp"
  cd "$BUILD_DIR" || die "cannot enter $BUILD_DIR"

  build_pappl
  build_lprint
  resign_local
  smoke_test

  info "Verifying the ZP 450 drivers are present"
  [ -x "$LPRINT" ] || die "$LPRINT is missing - the build did not complete"
  if "$LPRINT" drivers | grep -q '^epl2_4inch-203dpi-dt_zp450 '; then
    ok "epl2_4inch-203dpi-dt_zp450"
  else
    warn "ZP 450 EPL driver not registered; setup will fall back to $DRIVER_FALLBACK"
  fi
  if "$LPRINT" drivers | grep -q '^zpl_4inch-203dpi-dt_zp450 '; then
    ok "zpl_4inch-203dpi-dt_zp450"
  fi
}

# Only run when executed; package/build-pkg.sh sources this file to reuse
# fetch_and_verify, force_native_arch and the environment checks.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
