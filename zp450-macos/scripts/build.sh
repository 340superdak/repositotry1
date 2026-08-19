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

BREW_PACKAGES=(pkg-config libusb libpng jpeg-turbo openssl@3)

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

setup_build_env() {
  local brew_prefix
  brew_prefix="$(brew --prefix)"

  # PAPPL needs OpenSSL for TLS and libusb for USB devices; Homebrew keeps
  # openssl@3 keg-only, so its .pc files have to be added explicitly.
  export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${brew_prefix}/lib/pkgconfig:${brew_prefix}/opt/openssl@3/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
  export CPPFLAGS="-I${brew_prefix}/include ${CPPFLAGS:-}"
  export LDFLAGS="-L${brew_prefix}/lib ${LDFLAGS:-}"

  # Build for whatever architecture this Mac actually is; a universal binary
  # would only matter for redistribution, which this install does not do.
  info "Building for $(uname -m) against Homebrew at ${brew_prefix}"
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
    ./configure --prefix="$PREFIX" --with-tls=openssl --enable-libusb --disable-static
    make -j"$(sysctl -n hw.ncpu)"
    run_root make install
  )
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

    ./configure --prefix="$PREFIX"
    make -j"$(sysctl -n hw.ncpu)"
    run_root make install
  )
  ok "LPrint installed to $PREFIX"
}

main() {
  install_dependencies
  setup_build_env

  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR" || die "cannot enter $BUILD_DIR"

  build_pappl
  build_lprint

  info "Verifying the ZP 450 drivers are present"
  if "$LPRINT" drivers | grep -q '^epl2_4inch-203dpi-dt_zp450 '; then
    ok "epl2_4inch-203dpi-dt_zp450"
  else
    warn "ZP 450 EPL driver not registered; setup will fall back to $DRIVER_FALLBACK"
  fi
  if "$LPRINT" drivers | grep -q '^zpl_4inch-203dpi-dt_zp450 '; then
    ok "zpl_4inch-203dpi-dt_zp450"
  fi
}

main "$@"
