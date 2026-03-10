#!/bin/sh -x

root=$(pwd)

if test "x${CI_BUILD}" != "x"; then
    if test $(uname -s) = "Linux"; then
        dnf update -y
        dnf install -y wget flex bison jq readline readline-devel libffi libffi-devel tcl tcl-devel python3-devel zlib-devel cmake
        export PATH=/opt/python/cp312-cp312/bin:$PATH
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
    cd ${proj}/yosys
    git submodule update --init
    if test $? -ne 0; then exit 1; fi
    cd ${proj}
fi

cd ${proj}/yosys
make -j$(nproc) PREFIX=${release_dir}
if test $? -ne 0; then exit 1; fi

make install PREFIX=${release_dir}
if test $? -ne 0; then exit 1; fi

# Ensure all installed binaries have execute permission
chmod +x ${release_dir}/bin/*

# Build boolector SMT solver and install to bin
cd ${proj}
if test ! -d boolector; then
    git clone --depth=1 https://github.com/Boolector/boolector
    if test $? -ne 0; then exit 1; fi
fi
cd ${proj}/boolector
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


# Bundle the dv-flow-libyosys Python package into the release directory so
# that IVPM can pip-install it from the extracted tarball.
cp ${proj}/pyproject.toml ${release_dir}/
cp ${proj}/LICENSE ${release_dir}/
cp -r ${proj}/src ${release_dir}/

# Build the egg-info so the package metadata is present in the tarball.
cd ${release_dir}
pip install setuptools setuptools-scm --quiet
SETUPTOOLS_SCM_PRETEND_VERSION=${rls_version} pip install --no-build-isolation --no-deps -e . --quiet
if test $? -ne 0; then exit 1; fi

# Copy the ivpm.yaml so IVPM knows to prepend PATH after extraction.
cp ${proj}/ivpm.yaml ${release_dir}/

cd ${root}/release
tar czf yosys-bin-${rls_plat}-${rls_version}.tar.gz yosys-${rls_version}
