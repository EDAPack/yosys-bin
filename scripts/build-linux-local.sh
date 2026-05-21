#!/bin/sh
# Run the Linux manylinux build locally using Docker.
# Usage: scripts/build-linux-local.sh [manylinux_2_28_x86_64|manylinux_2_34_x86_64]
# Defaults to manylinux_2_28_x86_64.
#
# A named Docker volume (yosys-bin-stack-cache) is used to cache the Haskell
# Stack data directory (GHC toolchain + compiled packages) across runs so the
# first build's ~500 MB download is not repeated.

set -e

image=${1:-manylinux_2_28_x86_64}
yosys_version=${yosys_version:-1.0.0}

echo "Building with image: quay.io/pypa/${image}"
echo "Yosys version: ${yosys_version}"

# Create the Stack cache volume on first use.
docker volume create yosys-bin-stack-cache >/dev/null 2>&1 || true

exec docker run --rm \
    --volume "$(pwd):/io" \
    --volume "yosys-bin-stack-cache:/root/.stack" \
    --env CI_BUILD=1 \
    --env yosys_version="${yosys_version}" \
    --workdir /io \
    "quay.io/pypa/${image}" \
    /io/scripts/build.sh
