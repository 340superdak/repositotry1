#!/bin/bash
#
# Make a staged tree self-contained: copy every non-system dylib it depends on
# into <root>/lib and rewrite the load commands to @rpath, so the result runs
# on a Mac with no Homebrew and no developer tools.
#
# Usage: bundle-dylibs.sh <staged-prefix>
#   e.g. bundle-dylibs.sh /tmp/zp450-stage/usr/local/zp450
#

set -euo pipefail

ROOT="${1:?usage: bundle-dylibs.sh <staged-prefix>}"
LIBDIR="$ROOT/lib"

if [ -t 1 ]; then
  _b=$'\033[1m'; _g=$'\033[32m'; _y=$'\033[33m'; _r=$'\033[31m'; _n=$'\033[0m'
else
  _b=''; _g=''; _y=''; _r=''; _n=''
fi
info() { printf '%s==>%s %s\n' "$_b" "$_n" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$_g" "$_n" "$*"; }
warn() { printf '%swarning:%s %s\n' "$_y" "$_n" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$_r" "$_n" "$*" >&2; exit 1; }

# A dependency is "system" if it ships with macOS; everything else must be
# carried. Anything already rewritten to @rpath/@loader_path is done.
is_system_lib() {
  case "$1" in
    /usr/lib/*|/System/*|@rpath/*|@loader_path/*|@executable_path/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Direct dependencies of a Mach-O file, one per line.
deps_of() {
  otool -L "$1" | tail -n +2 | awk '{print $1}'
}

mkdir -p "$LIBDIR"

# Work queue: start with the executables and the libraries already staged.
queue=()
for f in "$ROOT"/bin/* "$LIBDIR"/*.dylib; do
  [ -f "$f" ] || continue
  # Skip shell wrappers and anything that is not Mach-O.
  file -b "$f" | grep -q 'Mach-O' || continue
  queue+=("$f")
done

[ "${#queue[@]}" -gt 0 ] || die "no Mach-O files found under $ROOT"

processed=""
while [ "${#queue[@]}" -gt 0 ]; do
  current="${queue[0]}"
  queue=("${queue[@]:1}")

  case " $processed " in *" $current "*) continue ;; esac
  processed="$processed $current"

  info "Inspecting $(basename "$current")"

  while read -r dep; do
    [ -n "$dep" ] || continue
    is_system_lib "$dep" && continue

    base="$(basename "$dep")"

    # A file's own id shows up in otool -L; rewrite it rather than copying
    # the file onto itself.
    if [ "$base" = "$(basename "$current")" ]; then
      install_name_tool -id "@rpath/$base" "$current" 2>/dev/null || true
      continue
    fi

    if [ ! -f "$LIBDIR/$base" ]; then
      [ -f "$dep" ] || die "dependency not found on disk: $dep (needed by $current)"
      cp "$dep" "$LIBDIR/$base"
      chmod u+w "$LIBDIR/$base"
      install_name_tool -id "@rpath/$base" "$LIBDIR/$base"
      ok "bundled $base"
      queue+=("$LIBDIR/$base")
    fi

    install_name_tool -change "$dep" "@rpath/$base" "$current"
  done < <(deps_of "$current")
done

# Executables look one directory up for lib/; libraries sit beside each other.
for f in "$ROOT"/bin/*; do
  [ -f "$f" ] || continue
  file -b "$f" | grep -q 'Mach-O' || continue
  install_name_tool -add_rpath "@loader_path/../lib" "$f" 2>/dev/null || true
done
for f in "$LIBDIR"/*.dylib; do
  [ -f "$f" ] || continue
  install_name_tool -add_rpath "@loader_path" "$f" 2>/dev/null || true
done

# install_name_tool invalidates signatures; re-sign, disabling library
# validation on the executables for the same Team ID reason as the source build.
ents="$(mktemp "${TMPDIR:-/tmp}/zp450-pkg-ents.XXXXXX")"
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

for f in "$LIBDIR"/*.dylib; do
  [ -f "$f" ] || continue
  codesign --force --sign - --timestamp=none "$f" >/dev/null 2>&1 || die "codesign failed: $f"
done
for f in "$ROOT"/bin/*; do
  [ -f "$f" ] || continue
  file -b "$f" | grep -q 'Mach-O' || continue
  codesign --force --sign - --timestamp=none --entitlements "$ents" "$f" >/dev/null 2>&1 || die "codesign failed: $f"
done
rm -f "$ents"

# Verify: nothing may still point at Homebrew or any other build-machine path.
info "Verifying the tree is self-contained"
leaked=0
for f in "$ROOT"/bin/* "$LIBDIR"/*.dylib; do
  [ -f "$f" ] || continue
  file -b "$f" | grep -q 'Mach-O' || continue
  while read -r dep; do
    [ -n "$dep" ] || continue
    if ! is_system_lib "$dep"; then
      warn "$(basename "$f") still references $dep"
      leaked=1
    fi
  done < <(deps_of "$f")
done
[ "$leaked" = "0" ] || die "the staged tree is not self-contained; it would fail on a clean Mac"

ok "all dependencies bundled and rewritten to @rpath"
