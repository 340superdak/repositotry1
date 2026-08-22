#!/bin/bash
#
# Build a double-clickable macOS installer package for the ZP 450 printer
# application. The result installs on a Mac with no Homebrew, no Xcode command
# line tools and no compiling: every library is carried inside the package.
#
# Run this on a Mac that CAN build (Homebrew + command line tools), then hand
# the .pkg to machines that cannot.
#
# Usage: ./build-pkg.sh [--version X.Y.Z]
#

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

# Installs into its own prefix so the package can never collide with a
# from-source install under /usr/local.
export PREFIX="/usr/local/zp450"
PKG_VERSION="1.0.0"
PKG_IDENTIFIER="org.zp450.printer"
STAGE="/tmp/zp450-pkg/stage"
OUT="$HERE/out"

while [ $# -gt 0 ]; do
  case "$1" in
    --version) PKG_VERSION="$2"; shift ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# Reuse the source build's helpers: architecture and CUPS checks, tarball
# fetching with checksums, and the universal-flag rewrite.
# shellcheck source=../scripts/build.sh
source "$REPO/scripts/build.sh"

STAGED_ROOT="$STAGE$PREFIX"

stage_build() {
  local name="$1" tarball="$2" url="$3" sha="$4"
  shift 4

  info "Building $name for packaging"
  fetch_and_verify "$url" "$tarball" "$sha"

  rm -rf "${tarball%.tar.gz}"
  tar xzf "$tarball"
  (
    cd "${tarball%.tar.gz}" || exit 1
    ./configure --prefix="$PREFIX" "$@" >"$BUILD_DIR/$name-configure.log" 2>&1 || {
      tail -20 "$BUILD_DIR/$name-configure.log" >&2
      die "$name configure failed"
    }
    force_native_arch
    make -j"$(sysctl -n hw.ncpu)" >"$BUILD_DIR/$name-build.log" 2>&1 || {
      tail -30 "$BUILD_DIR/$name-build.log" >&2
      die "$name build failed"
    }
    # DESTDIR (via BUILDROOT) stages the install without touching the system.
    make install DESTDIR="$STAGE" >/dev/null
  )
  ok "$name staged"
}

stage_runtime_files() {
  info "Staging runtime scripts and documentation"

  install -d "$STAGED_ROOT/share/zp450/scripts" "$STAGED_ROOT/share/zp450/launchd" \
             "$STAGED_ROOT/share/doc/zp450"

  local f
  for f in common.sh setup-queue.sh test-print.sh device-id.sh; do
    install -m 755 "$REPO/scripts/$f" "$STAGED_ROOT/share/zp450/scripts/$f"
  done
  install -m 644 "$REPO/launchd/org.zp450.lprint.plist.in" "$STAGED_ROOT/share/zp450/launchd/"
  install -m 644 "$REPO/README.md" "$STAGED_ROOT/share/doc/zp450/"
  install -m 644 "$REPO/docs/TROUBLESHOOTING.md" "$STAGED_ROOT/share/doc/zp450/"

  # Two commands users can run after installing, so they never need the repo.
  cat > "$STAGED_ROOT/bin/zp450-setup" <<'WRAP'
#!/bin/bash
# Create (or recreate) the ZP 450 print queues. Run this if the printer was not
# connected when the package was installed, or to change driver/media options:
#   sudo zp450-setup --zpl
set -euo pipefail
PREFIX="/usr/local/zp450"
export PREFIX ASSUME_YES=1
for arg in "$@"; do
  case "$arg" in
    --zpl) export DRIVER="zpl_4inch-203dpi-dt_zp450" DRIVER_FALLBACK="zpl_4inch-203dpi-dt" ;;
    --epl) export DRIVER="epl2_4inch-203dpi-dt_zp450" DRIVER_FALLBACK="epl2_4inch-203dpi-dt" ;;
    *) echo "usage: zp450-setup [--epl|--zpl]" >&2; exit 2 ;;
  esac
done
exec "$PREFIX/share/zp450/scripts/setup-queue.sh"
WRAP
  chmod 755 "$STAGED_ROOT/bin/zp450-setup"

  cat > "$STAGED_ROOT/bin/zp450-uninstall" <<'WRAP'
#!/bin/bash
# Remove the ZP 450 printer application: queues, daemon, and installed files.
set -euo pipefail
PREFIX="/usr/local/zp450"
LPRINT_QUEUE="${LPRINT_QUEUE:-zp450}"
CUPS_QUEUE="${CUPS_QUEUE:-ZP450}"
PLIST="/Library/LaunchDaemons/org.zp450.lprint.plist"

[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }

lpstat -p "$CUPS_QUEUE" >/dev/null 2>&1 && lpadmin -x "$CUPS_QUEUE" && echo "removed macOS queue $CUPS_QUEUE"
[ -x "$PREFIX/bin/lprint" ] && "$PREFIX/bin/lprint" delete -d "$LPRINT_QUEUE" 2>/dev/null && echo "removed LPrint queue $LPRINT_QUEUE"
launchctl bootout "system/org.zp450.lprint" 2>/dev/null || launchctl unload -w "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$PREFIX"
rm -f /private/var/lib/lprint.state
rm -rf /private/var/spool/lprint
pkgutil --forget org.zp450.printer >/dev/null 2>&1 || true
echo "ZP 450 printer application removed."
WRAP
  chmod 755 "$STAGED_ROOT/bin/zp450-uninstall"

  ok "runtime files staged"
}

smoke_test_staged() {
  info "Running the staged binary (proves the bundle is self-contained)"
  if ! "$STAGED_ROOT/bin/lprint" drivers >/dev/null 2>&1; then
    "$STAGED_ROOT/bin/lprint" drivers 2>&1 | head -10 >&2
    die "the staged lprint cannot run; the package would fail on a clean Mac"
  fi
  ok "staged lprint runs against its bundled libraries"
}

build_package() {
  info "Building the installer package"
  rm -rf "$OUT"
  mkdir -p "$OUT"

  pkgbuild \
    --root "$STAGE" \
    --scripts "$HERE/scripts" \
    --identifier "$PKG_IDENTIFIER" \
    --version "$PKG_VERSION" \
    --install-location "/" \
    --ownership recommended \
    "$OUT/zp450-component.pkg" >/dev/null

  productbuild \
    --distribution "$HERE/distribution.xml" \
    --resources "$HERE/resources" \
    --package-path "$OUT" \
    "$OUT/ZP450-Installer-$PKG_VERSION.pkg" >/dev/null

  rm -f "$OUT/zp450-component.pkg"
  ok "built $OUT/ZP450-Installer-$PKG_VERSION.pkg ($(du -h "$OUT/ZP450-Installer-$PKG_VERSION.pkg" | cut -f1))"
}

main_pkg() {
  check_architecture
  install_dependencies
  setup_build_env
  check_cups

  rm -rf "$STAGE"
  mkdir -p "$STAGE" "$BUILD_DIR"
  cd "$BUILD_DIR" || die "cannot enter $BUILD_DIR"

  stage_build pappl "pappl-${PAPPL_VERSION}.tar.gz" "$PAPPL_URL" "$PAPPL_SHA256" \
    --with-tls=openssl --enable-libusb --disable-static

  # LPrint must find the staged PAPPL rather than a system one.
  export PKG_CONFIG_SYSROOT_DIR="$STAGE"
  export PKG_CONFIG_PATH="$STAGED_ROOT/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
  export CPPFLAGS="-I$STAGED_ROOT/include ${CPPFLAGS:-}"
  export LDFLAGS="-L$STAGED_ROOT/lib ${LDFLAGS:-}"

  stage_build lprint "lprint-${LPRINT_VERSION}.tar.gz" "$LPRINT_URL" "$LPRINT_SHA256"

  stage_runtime_files
  bash "$HERE/bundle-dylibs.sh" "$STAGED_ROOT"
  smoke_test_staged
  build_package

  echo
  info "Done"
  echo "  Package : $OUT/ZP450-Installer-$PKG_VERSION.pkg"
  echo "  Installs to: $PREFIX (nothing else on the target Mac is touched)"
  echo "  Target needs: nothing - no Homebrew, no Xcode tools, no compiling"
}

main_pkg "$@"
