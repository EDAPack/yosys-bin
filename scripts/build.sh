#!/bin/sh -x

root=$(pwd)

if test "x${CI_BUILD}" != "x"; then
    if test $(uname -s) = "Linux"; then
        dnf update -y
        dnf install -y wget flex bison jq readline readline-devel libffi libffi-devel tcl tcl-devel python3-devel zlib-devel cmake glibc-static gcc-c++ patchelf
        export PATH=/opt/python/cp310-cp310/bin:$PATH
        rls_plat="manylinux-x64"
    elif test $(uname -s) = "Windows"; then
        rls_plat="windows-x64"
    fi
fi

proj=$(pwd)
if test "x${yosys_version}" != "x"; then
    rls_version=${yosys_version}
else
    rls_version=1.0.0
fi

release_dir="${root}/release/yosys-${rls_version}"
rm -rf ${release_dir}
mkdir -p ${release_dir}

if test ! -d yosys; then
    git clone https://github.com/YosysHQ/yosys
    if test $? -ne 0; then exit 1; fi
fi
# Allow git to operate on a directory that may be owned by the host user
# (relevant when running as root inside a container with a bind-mounted repo).
git config --global --add safe.directory ${proj}/yosys
cd ${proj}/yosys
git submodule update --init
if test $? -ne 0; then exit 1; fi
cd ${proj}

# Build yosys (pyosys Python bindings disabled).
cd ${proj}/yosys
make -j$(nproc) PREFIX=${release_dir}
if test $? -ne 0; then exit 1; fi

make install PREFIX=${release_dir}
if test $? -ne 0; then exit 1; fi

chmod +x ${release_dir}/bin/*

cd ${proj}

# ── yosys-slang plugin ────────────────────────────────────────────────────────
# yosys-slang provides a `read_slang` command for SystemVerilog elaboration.
# slang and fmt are bundled as submodules and statically linked, so the output
# slang.so has no external shared-library dependencies beyond what yosys itself
# requires.  C++20 is needed; the manylinux_2_34 default GCC (11+) is sufficient.
echo "=== Building yosys-slang ==="
if test ! -d ${proj}/yosys-slang; then
    git clone https://github.com/povik/yosys-slang ${proj}/yosys-slang
    if test $? -ne 0; then exit 1; fi
fi
git config --global --add safe.directory ${proj}
git config --global --add safe.directory ${proj}/yosys-slang
git config --global --add safe.directory ${proj}/yosys-slang/third_party/slang
git config --global --add safe.directory ${proj}/yosys-slang/third_party/fmt
cd ${proj}/yosys-slang
git submodule update --init --recursive
if test $? -ne 0; then exit 1; fi

cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DYOSYS_CONFIG=${release_dir}/bin/yosys-config \
    -DBUILD_AS_PLUGIN=ON
if test $? -ne 0; then exit 1; fi

cmake --build build -j$(nproc)
if test $? -ne 0; then exit 1; fi

mkdir -p ${release_dir}/share/yosys/plugins
cp build/slang.so ${release_dir}/share/yosys/plugins/
echo "  Installed: share/yosys/plugins/slang.so"
cd ${proj}

# Build boolector SMT solver and install to bin
if test ! -d boolector; then
    git clone --depth=1 https://github.com/Boolector/boolector
    if test $? -ne 0; then exit 1; fi
fi
cd ${proj}/boolector
# Create a cmake wrapper that injects CMAKE_POLICY_VERSION_MINIMUM=3.5 so that
# btor2tools (which has an old cmake_minimum_required) builds on modern CMake.
mkdir -p ${proj}/cmake-wrapper
cat > ${proj}/cmake-wrapper/cmake << 'CMAKEWRAP'
#!/bin/sh
exec /usr/bin/cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_EXE_LINKER_FLAGS="-L/usr/lib64" "$@"
CMAKEWRAP
chmod +x ${proj}/cmake-wrapper/cmake
export PATH=${proj}/cmake-wrapper:${PATH}
./contrib/setup-lingeling.sh
if test $? -ne 0; then exit 1; fi
./contrib/setup-btor2tools.sh
if test $? -ne 0; then exit 1; fi
./configure.sh
if test $? -ne 0; then exit 1; fi
cd build
make -j$(nproc)
if test $? -ne 0; then exit 1; fi
cp bin/boolector ${release_dir}/bin/
chmod +x ${release_dir}/bin/boolector
cd ${proj}

# ── sby (SymbiYosys) ──────────────────────────────────────────────────────────
# sby is a formal verification front-end for Yosys.  It is pure Python so no
# compilation is needed; make install copies the Python scripts and the launcher.
echo "=== Installing sby ==="
if test -d ${proj}/packages/sby; then
    sby_src=${proj}/packages/sby
elif test ! -d ${proj}/sby; then
    git clone https://github.com/YosysHQ/sby ${proj}/sby
    if test $? -ne 0; then exit 1; fi
    sby_src=${proj}/sby
else
    sby_src=${proj}/sby
fi
git config --global --add safe.directory ${sby_src}
cd ${sby_src}
make install PREFIX=${release_dir}
if test $? -ne 0; then exit 1; fi
cd ${proj}

# ── mcy (Mutation Cover with Yosys) ──────────────────────────────────────────
# mcy is pure Python (plus an optional Qt GUI which we skip here because the
# build container does not have Qt installed).  Install scripts manually.
echo "=== Installing mcy ==="
if test -d ${proj}/packages/mcy; then
    mcy_src=${proj}/packages/mcy
elif test ! -d ${proj}/mcy; then
    git clone https://github.com/YosysHQ/mcy ${proj}/mcy
    if test $? -ne 0; then exit 1; fi
    mcy_src=${proj}/mcy
else
    mcy_src=${proj}/mcy
fi
git config --global --add safe.directory ${mcy_src}
mkdir -p ${release_dir}/bin
install ${mcy_src}/mcy.py ${release_dir}/bin/mcy
install ${mcy_src}/mcy-dash.py ${release_dir}/bin/mcy-dash
mkdir -p ${release_dir}/share/mcy/dash
cp -r ${mcy_src}/dash/. ${release_dir}/share/mcy/dash/.
mkdir -p ${release_dir}/share/mcy/scripts
cp -r ${mcy_src}/scripts/. ${release_dir}/share/mcy/scripts/.
cd ${proj}

# ── eqy (Equivalence Check with Yosys) ───────────────────────────────────────
# eqy ships three Yosys plugins (.so) that must be compiled against the already-
# installed yosys headers via yosys-config --build.
echo "=== Building and installing eqy ==="
if test -d ${proj}/packages/eqy; then
    eqy_src=${proj}/packages/eqy
elif test ! -d ${proj}/eqy; then
    git clone https://github.com/YosysHQ/eqy ${proj}/eqy
    if test $? -ne 0; then exit 1; fi
    eqy_src=${proj}/eqy
else
    eqy_src=${proj}/eqy
fi
git config --global --add safe.directory ${eqy_src}
cd ${eqy_src}
make install PREFIX=${release_dir} YOSYS_CONFIG=${release_dir}/bin/yosys-config
if test $? -ne 0; then exit 1; fi
cd ${proj}

# ── Bundle non-guaranteed shared libraries ────────────────────────────────────
# The release must be self-contained: any library that is not part of the base
# OS on every supported target (glibc 2.34+ / manylinux_2_34) is copied into
# lib/ and the ELFs that need it are patched with an $ORIGIN-relative RPATH so
# the dynamic linker finds the bundled copy first.
#
# Libraries bundled here and why they are not "nearly-guaranteed":
#   libcrypt.so.2  – provided by libxcrypt; absent by default on Ubuntu 22.04+
#                    and many other non-RHEL distros (they ship only .so.1)
#   libreadline.so.8 – readline 8; not always installed (some systems have 7)
#   libffi.so.8    – libffi 3.4; not always installed on non-devel systems
#   libtcl8.6.so   – Tcl 8.6; not always installed
#   libtinfo.so.6  – ncurses 6 (terminal DB); not always present separately
#
# Libraries intentionally NOT bundled (present on every glibc 2.34+ system):
#   libc, libm, libgcc_s, libstdc++ (guaranteed by manylinux ABI), libz
echo "=== Bundling non-guaranteed shared libraries ==="
mkdir -p ${release_dir}/lib

bundle_lib() {
    # bundle_lib <soname>  – copy the real file (resolving symlinks) and create
    # a soname symlink in ${release_dir}/lib/ if the library is found.
    soname="$1"
    found=$(ldconfig -p 2>/dev/null | grep " ${soname} " | awk '{print $NF}' | head -1)
    if test -z "${found}"; then
        found=$(find /lib64 /usr/lib64 /lib /usr/lib -name "${soname}" 2>/dev/null | head -1)
    fi
    if test -n "${found}"; then
        # Copy the real file (dereference symlinks so we get the actual .so.X.Y.Z)
        real=$(readlink -f "${found}")
        cp "${real}" ${release_dir}/lib/
        realname=$(basename "${real}")
        # Create soname symlink if the real name differs (e.g. libcrypt.so.2.0.0 → libcrypt.so.2)
        if test "${realname}" != "${soname}"; then
            ln -sf "${realname}" ${release_dir}/lib/${soname}
        fi
        echo "  Bundled ${soname} (${real})"
        return 0
    else
        echo "  WARNING: ${soname} not found in build environment – skipping"
        return 1
    fi
}

for soname in libcrypt.so.2 libreadline.so.8 libffi.so.8 libtcl8.6.so libtinfo.so.6; do
    bundle_lib "${soname}"
done

# Patch RPATH on every installed ELF that links one of the bundled libraries.
# We add $ORIGIN-relative paths so the binary finds lib/ regardless of where
# the release tree is installed.
patch_rpath() {
    elf="$1"
    rpath="$2"
    if ! file "${elf}" 2>/dev/null | grep -q ELF; then return; fi
    if ldd "${elf}" 2>/dev/null | grep -qE 'libcrypt\.so\.2|libreadline\.so\.8|libffi\.so\.8|libtcl8\.6\.so|libtinfo\.so\.6'; then
        patchelf --add-rpath "${rpath}" "${elf}"
        echo "  RPATH '${rpath}' -> ${elf#${release_dir}/}"
    fi
}

# bin/* are one level below the release root → ../lib
for elf in ${release_dir}/bin/*; do
    patch_rpath "${elf}" '$ORIGIN/../lib'
done

# lib/yosys/*.so is two levels below the release root → ../../lib
for elf in ${release_dir}/lib/yosys/*.so; do
    patch_rpath "${elf}" '$ORIGIN/../../lib'
done

# share/yosys/plugins/*.so is three levels below the release root → ../../../lib
for elf in ${release_dir}/share/yosys/plugins/*.so; do
    patch_rpath "${elf}" '$ORIGIN/../../../lib'
done

echo "=== Library bundling complete ==="

# Flat-layout Python package setup.
# dv_flow/ goes directly at the release root (not under src/) so that
# PYTHONPATH=<release_dir> and pip install -e <release_dir> both work
# without any extra path components.  dv_flow has no __init__.py so it
# remains an implicit namespace package compatible with other dv_flow.* pkgs.
mkdir -p ${release_dir}/dv_flow
cp -r ${proj}/src/dv_flow/libyosys ${release_dir}/dv_flow/

# Write the release pyproject.toml with a hardcoded version (no setuptools-scm
# dependency at install time — the release tree is not a git repo).
pip_version=$(echo ${rls_version} | sed -e 's/^[^0-9]*//')
sed "s/%%VERSION%%/${pip_version}/" \
    ${proj}/scripts/pyproject-release.toml > ${release_dir}/pyproject.toml

cp ${proj}/LICENSE ${release_dir}/
cp ${proj}/ivpm.yaml ${release_dir}/
cp ${proj}/scripts/export.envrc ${release_dir}/

# Pre-generate egg-info so package metadata is present in the tarball.
cd ${release_dir}
pip install setuptools --quiet
pip install --no-build-isolation --no-deps -e . --quiet
if test $? -ne 0; then exit 1; fi

cd ${root}/release
tar czf yosys-bin-${rls_plat}-${rls_version}.tar.gz yosys-${rls_version}
