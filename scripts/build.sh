#!/usr/bin/env bash
# yosys-bin build driver.
#
# Builds yosys (with its vendored slang frontend) + boolector + sby + mcy +
# eqy + sv2v from the exact commits resolved by edapack-common's
# resolve-inputs.py and emits a release manifest. Non-guaranteed shared libraries are bundled with $ORIGIN rpaths so
# the release is self-contained.
#
# Runs in CI (reusable workflow) and locally (local-build.sh). All transient
# state goes to WORK_DIR (the old in-tree cmake-wrapper/ that caused root-owned
# files is now created under WORK_DIR); tarball + manifest land in OUT_DIR; the
# source tree is never written to.
set -euo pipefail

# --- locate edapack-common --------------------------------------------------
if [ -z "${EC_COMMON:-}" ]; then
    _repo="$(cd "$(dirname "$0")/.." && pwd)"
    for _c in "$_repo/packages/edapack-common" "$_repo/../edapack-common"; do
        if [ -f "$_c/scripts/build-common.sh" ]; then EC_COMMON="$_c"; break; fi
    done
fi
if [ -z "${EC_COMMON:-}" ] || [ ! -f "$EC_COMMON/scripts/build-common.sh" ]; then
    echo "ERROR: edapack-common not found. Set EC_COMMON or place edapack-common beside yosys-bin." >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$EC_COMMON/scripts/build-common.sh"

: "${EC_PACKAGE:=yosys-bin}"
export EC_PACKAGE
ec_init_dirs
ec_prepare_candidate

os="$(uname -s)"
plat="${EC_IMAGE_NAME:-}"
njobs="$(nproc 2>/dev/null || echo 4)"

# Provision the stock manylinux image (EC_INSTALL_DEPS=1 in CI/local).
if [ "${EC_INSTALL_DEPS:-0}" = "1" ] && [ "$os" = "Linux" ]; then
    dnf install -y wget flex bison jq readline readline-devel libffi libffi-devel \
        tcl tcl-devel python3-devel zlib-devel cmake glibc-static gcc-c++ patchelf \
        gmp-devel ncurses-devel || true
    command -v stack >/dev/null 2>&1 || curl -sSL https://get.haskellstack.org/ | sh -s - -d /usr/local/bin || true
    [ -d /opt/python/cp310-cp310/bin ] && export PATH=/opt/python/cp310-cp310/bin:$PATH
    # Yosys needs bison >= 3.6; manylinux_2_28 (AlmaLinux 8) ships 3.0.4 — build
    # 3.8.2 from source when the system bison is too old.
    bison_ver="$(bison --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo 0.0)"
    bmaj="${bison_ver%%.*}"; bmin="${bison_ver#*.}"
    if [ "${bmaj:-0}" -lt 3 ] || { [ "${bmaj:-0}" -eq 3 ] && [ "${bmin:-0}" -lt 6 ]; }; then
        ec_log "system bison ${bison_ver} too old; building bison 3.8.2"
        curl -sL https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.gz -o /tmp/bison.tar.gz
        tar -C /tmp -xzf /tmp/bison.tar.gz
        ( cd /tmp/bison-3.8.2 && ./configure --prefix=/usr/local && make -j"$njobs" && make install )
        hash -r
    fi
    # Yosys >= 0.67 is built with CMake and requires >= 3.28; AlmaLinux 8 ships
    # older. Take the PyPI wheel, which is current and needs no extra repos.
    # NOTE: this only shadows `cmake` on PATH — the boolector policy shim below
    # deliberately calls /usr/bin/cmake, which must stay the system one.
    cmake_ver="$(cmake --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo 0.0)"
    cmaj="${cmake_ver%%.*}"; cmin="${cmake_ver#*.}"
    if [ "${cmaj:-0}" -lt 3 ] || { [ "${cmaj:-0}" -eq 3 ] && [ "${cmin:-0}" -lt 28 ]; }; then
        ec_log "system cmake ${cmake_ver} too old for yosys; installing the PyPI wheel"
        pip install --quiet --upgrade cmake
        hash -r
        ec_log "cmake now $(cmake --version | head -1)"
    fi
fi

# --- glibc-specific bundle set (label + sonames) ----------------------------
glibc_ver="$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+$' || echo 0)"
case "$glibc_ver" in
    2.17) bundle_sonames="libcrypt.so.1 libreadline.so.6 libffi.so.6 libtcl8.6.so libtinfo.so.6 libgmp.so.10"; : "${plat:=manylinux2014_x86_64}" ;;
    2.28) bundle_sonames="libcrypt.so.1 libreadline.so.7 libffi.so.6 libtcl8.6.so libtinfo.so.6 libgmp.so.10"; : "${plat:=manylinux_2_28_x86_64}" ;;
    *)    bundle_sonames="libcrypt.so.2 libreadline.so.8 libffi.so.8 libtcl8.6.so libtinfo.so.6 libgmp.so.10"; : "${plat:=manylinux_2_34_x86_64}" ;;
esac
ec_log "glibc $glibc_ver -> plat $plat; bundling: $bundle_sonames"

release_root="$WORK_DIR/release/yosys"
rm -rf "$release_root"; mkdir -p "$release_root"

# cmake policy shim for btor2tools' ancient cmake_minimum_required — created in
# WORK_DIR (never the source tree) and used only for the boolector build.
wrapper_dir="$WORK_DIR/cmake-wrapper"; mkdir -p "$wrapper_dir"
cat > "$wrapper_dir/cmake" <<'CMAKEWRAP'
#!/bin/sh
exec /usr/bin/cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_EXE_LINKER_FLAGS="-L/usr/lib64" "$@"
CMAKEWRAP
chmod +x "$wrapper_dir/cmake"

# --- clone resolved inputs --------------------------------------------------
yosys_src="$(ec_clone_input yosys "$(ec_input_get yosys repo)" "$(ec_input_get yosys resolved_sha)")"
boolector_src="$(ec_clone_input boolector "$(ec_input_get boolector repo)" "$(ec_input_get boolector resolved_sha)")"
sby_src="$(ec_clone_input sby "$(ec_input_get sby repo)" "$(ec_input_get sby resolved_sha)")"
mcy_src="$(ec_clone_input mcy "$(ec_input_get mcy repo)" "$(ec_input_get mcy resolved_sha)")"
eqy_src="$(ec_clone_input eqy "$(ec_input_get eqy repo)" "$(ec_input_get eqy resolved_sha)")"
sv2v_src="$(ec_clone_input sv2v "$(ec_input_get sv2v repo)" "$(ec_input_get sv2v resolved_sha)")"

# --- yosys core -------------------------------------------------------------
# Upstream deleted the Makefile in a727e7f6 ("Migrate build system to CMake");
# v0.68 is CMake-only. This follows the build documented in yosys' README.
#
# slang is no longer a separate plugin: yosys vendors povik's frontend as the
# libs/slang + frontends/slang/lib submodules and builds it in-tree, so
# `read_slang` is a built-in command and `plugin -i slang` is no longer needed.
# ec_clone_input clones submodules recursively, so both are present. Passed
# explicitly because we depend on it rather than on the default staying OFF.
rm -rf "$yosys_src/build"
cmake -S "$yosys_src" -B "$yosys_src/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$release_root" \
    -DYOSYS_WITHOUT_SLANG=OFF
cmake --build "$yosys_src/build" --parallel "$njobs"
cmake --install "$yosys_src/build"
chmod +x "$release_root"/bin/* 2>/dev/null || true
ec_require_file "$release_root/bin/yosys" "yosys driver"
ec_require_file "$release_root/bin/yosys-config" "yosys-config"

# --- boolector (uses the policy-shim cmake) ---------------------------------
(
    cd "$boolector_src"
    export PATH="$wrapper_dir:$PATH"
    ./contrib/setup-lingeling.sh
    ./contrib/setup-btor2tools.sh
    ./configure.sh
    make -C build -j"$njobs"
)
cp "$boolector_src/build/bin/boolector" "$release_root/bin/"
chmod +x "$release_root/bin/boolector"

# --- sby (pure Python) ------------------------------------------------------
make -C "$sby_src" install PREFIX="$release_root"

# --- mcy (pure Python + dash assets) ----------------------------------------
mkdir -p "$release_root/bin"
install "$mcy_src/mcy.py" "$release_root/bin/mcy"
install "$mcy_src/mcy-dash.py" "$release_root/bin/mcy-dash"
mkdir -p "$release_root/share/mcy/dash" "$release_root/share/mcy/scripts"
cp -r "$mcy_src/dash/." "$release_root/share/mcy/dash/."
cp -r "$mcy_src/scripts/." "$release_root/share/mcy/scripts/."

# --- eqy (plugins built against installed yosys) ----------------------------
make -C "$eqy_src" install PREFIX="$release_root" YOSYS_CONFIG="$release_root/bin/yosys-config"

# --- sv2v (Haskell / Stack) -------------------------------------------------
(
    cd "$sv2v_src"
    mkdir -p "${HOME}/.stack"
    grep -q 'allow-different-user' "${HOME}/.stack/config.yaml" 2>/dev/null \
        || echo 'allow-different-user: true' >> "${HOME}/.stack/config.yaml"
    make
)
cp "$sv2v_src/bin/sv2v" "$release_root/bin/"
chmod +x "$release_root/bin/sv2v"

# --- bundle non-guaranteed shared libraries + patch rpaths ------------------
mkdir -p "$release_root/lib"
bundle_lib() {
    local soname="$1" found real realname
    # `|| true`: with `set -o pipefail`, a no-match grep / non-zero find would
    # otherwise abort the whole build when a soname isn't in the ldconfig cache.
    found="$(ldconfig -p 2>/dev/null | grep " ${soname} " | awk '{print $NF}' | head -1 || true)"
    [ -n "$found" ] || found="$(find /lib64 /usr/lib64 /lib /usr/lib -name "${soname}" 2>/dev/null | head -1 || true)"
    [ -n "$found" ] || { ec_log "WARNING: ${soname} not found — skipping"; return 0; }
    real="$(readlink -f "$found")"
    cp "$real" "$release_root/lib/"
    realname="$(basename "$real")"
    [ "$realname" != "$soname" ] && ln -sf "$realname" "$release_root/lib/${soname}"
    ec_log "bundled ${soname} (${real})"
}
for soname in $bundle_sonames; do bundle_lib "$soname"; done

bundle_pattern="$(echo "$bundle_sonames" | tr ' ' '\n' | sed 's/\./\\./g' | tr '\n' '|' | sed 's/|$//')"
patch_rpath() {
    local elf="$1" rpath="$2"
    file "$elf" 2>/dev/null | grep -q ELF || return 0
    if ldd "$elf" 2>/dev/null | grep -qE "$bundle_pattern"; then
        patchelf --add-rpath "$rpath" "$elf" && ec_log "rpath '$rpath' -> ${elf#"$release_root"/}"
    fi
}
for elf in "$release_root"/bin/*; do [ -e "$elf" ] && patch_rpath "$elf" '$ORIGIN/../lib'; done
for elf in "$release_root"/lib/yosys/*.so; do [ -e "$elf" ] && patch_rpath "$elf" '$ORIGIN/../../lib'; done
for elf in "$release_root"/share/yosys/plugins/*.so; do [ -e "$elf" ] && patch_rpath "$elf" '$ORIGIN/../../../lib'; done

# --- dv_flow python package + release pyproject -----------------------------
mkdir -p "$release_root/dv_flow"
cp -r "$SRC_DIR/src/dv_flow/libyosys" "$release_root/dv_flow/"
pip_version="$(echo "$EC_VERSION" | sed -e 's/^[^0-9]*//')"
sed "s/%%VERSION%%/${pip_version}/" "$SRC_DIR/scripts/pyproject-release.toml" > "$release_root/pyproject.toml"
cp "$SRC_DIR/LICENSE" "$release_root/"

# --- shared release tail (skills + envrc + ivpm.yaml + manifest) ------------
# ivpm.yaml now comes from scripts/release-ivpm.yaml via ec_stage_release_ivpm,
# not from this repo's own ivpm.yaml (which describes the *build*).
ec_finalize_release "$SRC_DIR" "$release_root" "$CANDIDATE_JSON"

# Pre-generate egg-info so package metadata ships in the tarball.
( cd "$release_root" && pip install setuptools --quiet && pip install --no-build-isolation --no-deps -e . --quiet )

tarball="yosys-bin-${plat}-${EC_VERSION}.tar.gz"
ec_make_tarball "$release_root" "$tarball"
ec_log "build complete: $tarball"
