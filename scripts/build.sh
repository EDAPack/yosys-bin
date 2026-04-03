#!/bin/sh -x

root=$(pwd)

if test "x${CI_BUILD}" != "x"; then
    if test $(uname -s) = "Linux"; then
        dnf update -y
        dnf install -y wget flex bison jq readline readline-devel libffi libffi-devel tcl tcl-devel python3-devel zlib-devel cmake glibc-static gcc-c++
        # Use Python 3.10 as the base build interpreter (minimum supported version).
        # Per-version libyosys.cpython-3XX-*.so files are built in a loop below.
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

# Install Python build dependencies needed by pyosys (pybind11 v3 + header parser).
pip install "pybind11>=3,<4" cxxheaderparser --quiet
if test $? -ne 0; then exit 1; fi

# Patch yosys/Makefile:
#   Strip -lpython3.XX from LIBS so libyosys.so does not embed a link against
#   a specific libpython version.  Python symbols are resolved at runtime from
#   the already-running interpreter, so the same .so works with Python 3.10-3.14.
#
# Also remove any stale -DPy_LIMITED_API flag that may have been left by a
# previous build attempt (pybind11 3.x does not fully support Py_LIMITED_API).
python3 - << 'PYEOF'
import sys
path = 'yosys/Makefile'
with open(path) as f:
    content = f.read()

patches = [
    # Strip version-specific -lpython3.XX from LIBS (used by libyosys.so).
    (
        'LIBS += $(shell $(PYTHON_CONFIG) --libs)',
        'LIBS += $(filter-out -lpython%,$(shell $(PYTHON_CONFIG) --libs))',
    ),
    # Also strip from EXE_LIBS (embed config used by yosys binary & yosys-filterlib).
    (
        'EXE_LIBS += $(filter-out $(LIBS),$(shell $(PYTHON_CONFIG_FOR_EXE) --libs))',
        'EXE_LIBS += $(filter-out -lpython% $(LIBS),$(shell $(PYTHON_CONFIG_FOR_EXE) --libs))',
    ),
    # Allow Python C API symbols to remain unresolved at link time in executables.
    # On manylinux, libpython is not available as a shared library; the symbols
    # are resolved at runtime from the running interpreter (for libyosys.so) or
    # are simply never called in the yosys CLI binary (which does not need Python
    # embedding in our binary release).
    (
        'CXXFLAGS += $(shell $(PYTHON_CONFIG) --includes) -DYOSYS_ENABLE_PYTHON',
        'CXXFLAGS += $(shell $(PYTHON_CONFIG) --includes) -DYOSYS_ENABLE_PYTHON\nLINKFLAGS += -Wl,--unresolved-symbols=ignore-in-object-files',
    ),
]
# Reverse any stale Py_LIMITED_API patch from a previous build run.
reverses = [
    (
        'CXXFLAGS += $(shell $(PYTHON_CONFIG) --includes) -DYOSYS_ENABLE_PYTHON -DPy_LIMITED_API=0x030a0000',
        'CXXFLAGS += $(shell $(PYTHON_CONFIG) --includes) -DYOSYS_ENABLE_PYTHON',
    ),
]

changed = False
for old, new in reverses:
    if old in content:
        content = content.replace(old, new, 1)
        changed = True
        print(f'Reversed stale patch: {old[:80]}...')
    else:
        print(f'Stale patch not present (ok): {old[:60]}...')

for old, new in patches:
    if new in content:
        print(f'Already patched: {new[:70]}...')
    elif old in content:
        content = content.replace(old, new, 1)
        changed = True
        print(f'Patched: {old[:70]}...')
    else:
        print('ERROR: patch target not found in yosys/Makefile:', file=sys.stderr)
        print('  ' + old, file=sys.stderr)
        sys.exit(1)
if changed:
    with open(path, 'w') as f:
        f.write(content)
    print('Patches applied to yosys/Makefile.')
else:
    print('yosys/Makefile already patched.')
PYEOF
if test $? -ne 0; then exit 1; fi

# Full yosys build using cp310 as the base Python.  All yosys .o files are
# compiled once here; the per-version pyosys loop below only recompiles the
# small set of Python-specific objects for each additional interpreter.
cd ${proj}/yosys
make -j$(nproc) ENABLE_PYOSYS=1 PREFIX=${release_dir}
if test $? -ne 0; then exit 1; fi

# Install binaries, headers, share, and the pyosys package skeleton.
# PYTHON_DESTDIR places pyosys/ directly at the release root (flat layout).
make install ENABLE_PYOSYS=1 PREFIX=${release_dir} PYTHON_DESTDIR=${release_dir}
if test $? -ne 0; then exit 1; fi

chmod +x ${release_dir}/bin/*
chmod +x ${release_dir}/pyosys/yosys-abc

# Remove the generic libyosys.so installed above; it will be replaced by
# cpython-version-tagged copies built in the per-version loop below.
rm -f ${release_dir}/pyosys/libyosys.so

# ── Per-Python-version libyosys.so build ─────────────────────────────────────
# pybind11 v3 embeds PY_VERSION_HEX at compile time and rejects mismatches at
# import time.  We therefore compile a separate libyosys.cpython-3XX-*.so for
# each supported Python version.
#
# Only the four Python-specific object files need recompiling between versions;
# the rest of the yosys objects (compiled above) are reused as-is.
PYTHON_OBJECTS="pyosys/wrappers.o kernel/drivers.o kernel/yosys.o passes/cmds/plugin.o"
pyosys_failed=0
for PYVER in cp310-cp310 cp311-cp311 cp312-cp312 cp313-cp313; do
    PYBIN="/opt/python/${PYVER}/bin"
    if test ! -d "${PYBIN}"; then
        echo "  Skipping ${PYVER} (not available)"
        continue
    fi
    echo "=== Building libyosys.so for ${PYVER} ==="
    ${PYBIN}/pip install "pybind11>=3,<4" cxxheaderparser --quiet
    # Remove only the Python-specific .o files so make recompiles them with the
    # correct Python headers while reusing all other objects from the base build.
    rm -f ${PYTHON_OBJECTS}
    make -j$(nproc) ENABLE_PYOSYS=1 PYTHON_EXECUTABLE=${PYBIN}/python3 libyosys.so
    if test $? -ne 0; then
        echo "  FAILED to build libyosys.so for ${PYVER}"
        pyosys_failed=1
        continue
    fi
    EXT_SUFFIX=$(${PYBIN}/python3 -c "import sysconfig; print(sysconfig.get_config_var('EXT_SUFFIX'))")
    cp libyosys.so ${release_dir}/pyosys/libyosys${EXT_SUFFIX}
    echo "  Installed: pyosys/libyosys${EXT_SUFFIX}"
done
if test ${pyosys_failed} -ne 0; then exit 1; fi

cd ${proj}

# Ensure all installed binaries have execute permission
chmod +x ${release_dir}/bin/*

# ── yosys-slang plugin ────────────────────────────────────────────────────────
# yosys-slang provides a `read_slang` command for SystemVerilog elaboration.
# slang and fmt are bundled as submodules and statically linked, so the output
# slang.so has no external shared-library dependencies beyond what yosys itself
# requires.  C++20 is needed; the manylinux_2_34 default GCC (11+) is sufficient.
echo "=== Building yosys-slang ==="
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
# Also place the plugin inside pyosys/ so it is captured by the
# package-data glob "share/**/*" when the release is pip-installed.
mkdir -p ${release_dir}/pyosys/share/yosys/plugins
cp build/slang.so ${release_dir}/pyosys/share/yosys/plugins/
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

# Pre-generate egg-info so package metadata is present in the tarball.
cd ${release_dir}
pip install setuptools --quiet
pip install --no-build-isolation --no-deps -e . --quiet
if test $? -ne 0; then exit 1; fi

# ── Cross-version smoke tests ─────────────────────────────────────────────────
# Each Python version loads its own cpython-tagged libyosys.so from pyosys/.
echo "=== Cross-version pyosys tests ==="
test_failed=0
for PYVER in cp310-cp310 cp311-cp311 cp312-cp312 cp313-cp313; do
    PYBIN="/opt/python/${PYVER}/bin"
    if test ! -d "${PYBIN}"; then
        echo "  Skipping ${PYVER} (not available in this environment)"
        continue
    fi
    echo "  Testing ${PYVER}..."
    ${PYBIN}/pip install pytest --quiet
    PYTHONPATH=${release_dir} ${PYBIN}/python3 -m pytest \
        ${proj}/yosys/tests/pyosys/ -x -q --tb=short
    rc=$?
    # pytest exit code 5 = no tests collected (not a failure).
    if test ${rc} -ne 0 && test ${rc} -ne 5; then
        echo "  FAILED on ${PYVER} (exit ${rc})"
        test_failed=1
    else
        echo "  OK on ${PYVER}"
    fi
done
if test ${test_failed} -ne 0; then
    echo "Cross-version pyosys tests failed — aborting."
    exit 1
fi

cd ${root}/release
tar czf yosys-bin-${rls_plat}-${rls_version}.tar.gz yosys-${rls_version}
