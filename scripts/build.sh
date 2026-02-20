#!/bin/sh -x

root=$(pwd)

if test "x${CI_BUILD}" != "x"; then
    if test $(uname -s) = "Linux"; then
        dnf update -y
        dnf install -y wget flex bison jq readline readline-devel libffi libffi-devel tcl tcl-devel python3-devel zlib-devel
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

cd ${root}/release

tar czf yosys-${rls_plat}-${rls_version}.tar.gz yosys-${rls_version}
