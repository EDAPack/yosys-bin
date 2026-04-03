# Plugin Integration Plan: yosys-slang and ghdl-yosys-plugin

## Background

`yosys-bin` builds portable (manylinux) Yosys binaries and publishes them as
versioned GitHub releases.  The build runs inside `quay.io/pypa/manylinux_2_34_x86_64`
(AlmaLinux 8-based) and is orchestrated by `scripts/build.sh`.  The primary
artefact is a tarball containing `bin/`, `share/yosys/`, `pyosys/` (multi-version
cpython bindings), and `dv_flow/libyosys/` (DV-Flow task library).

Two Yosys plugins are candidates for inclusion:

| Plugin | Repo | Language | Dependencies |
|--------|------|----------|--------------|
| **yosys-slang** | https://github.com/povik/yosys-slang | C++20 | slang (bundled), fmt (bundled) |
| **ghdl-yosys-plugin** | https://github.com/ghdl/ghdl-yosys-plugin | C++ + Ada | GHDL (built from source), libghdl |

---

## Priority 1 — yosys-slang

### Why it's straightforward

- The source tree is **already present** in the repo as `yosys-slang/` (submodule).
- All runtime dependencies (slang, fmt) are **bundled as git submodules** inside
  `yosys-slang/third_party/` and are **statically linked** into the output `slang.so`.
  There are no extra shared-library dependencies at runtime.
- Uses CMake; the `cmake/FindYosys.cmake` helper simply runs `yosys-config` to
  locate the already-installed Yosys headers and flags — so building after the
  main Yosys install step is natural.
- The manylinux_2_34 image ships GCC 14 (via `gcc-toolset-14`), which fully
  supports C++20.
- The supported Yosys range (0.52–0.63) covers the versions we build against.

### What needs to be verified

1. **GCC version in the container.** yosys-slang requires GCC ≥ 11 (or Clang ≥ 17).
   `manylinux_2_34` provides GCC 14 via devtoolset, but the default `gcc` may be
   GCC 8.  Need to activate the toolset or pass explicit compiler paths to CMake.
   Verify with: `docker run quay.io/pypa/manylinux_2_34_x86_64 gcc --version`
2. **Submodule state.** Confirm `yosys-slang/third_party/slang/` and
   `yosys-slang/third_party/fmt/` are populated (run
   `git submodule update --init --recursive yosys-slang`).
3. **cmake version.** yosys-slang requires CMake ≥ 3.20.  The container ships a
   recent cmake already (verified: `cmake` is in the existing `dnf install` list
   in `build.sh`).

### Build steps to add to `scripts/build.sh`

Insert the following block **after** the `make install … PREFIX=${release_dir}`
step for Yosys and **before** the Boolector block:

```sh
# ── yosys-slang plugin ────────────────────────────────────────────────────────
echo "=== Building yosys-slang ==="
git config --global --add safe.directory ${proj}/yosys-slang
git config --global --add safe.directory ${proj}/yosys-slang/third_party/slang
cd ${proj}/yosys-slang
# Ensure bundled submodules are populated
git submodule update --init --recursive
if test $? -ne 0; then exit 1; fi

# Activate GCC 14 toolset if present (manylinux_2_34 default gcc may be < 11)
if test -f /opt/rh/gcc-toolset-14/enable; then
    . /opt/rh/gcc-toolset-14/enable
elif test -f /opt/rh/gcc-toolset-13/enable; then
    . /opt/rh/gcc-toolset-13/enable
fi

cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DYOSYS_CONFIG=${release_dir}/bin/yosys-config \
    -DBUILD_AS_PLUGIN=ON
if test $? -ne 0; then exit 1; fi

cmake --build build -j$(nproc)
if test $? -ne 0; then exit 1; fi

# Install slang.so into the Yosys plugins directory inside the release
mkdir -p ${release_dir}/share/yosys/plugins
cp build/slang.so ${release_dir}/share/yosys/plugins/
echo "  Installed: share/yosys/plugins/slang.so"
cd ${proj}
```

### Release artefact

`share/yosys/plugins/slang.so` is placed inside the tarball.  Users load it with:

```
yosys -m slang
```

or (with the tarball on PATH) by placing a `.yosys_plugins` config file or
passing the full path.

### CI changes

- Add `cmake` check (already present) and a minimal C++20 smoke-test step.
- Optionally upload a standalone `slang.so` artefact alongside the main tarball
  for users who have their own Yosys install.

---

## Priority 2 — ghdl-yosys-plugin

### Why it's harder

- **GHDL must be compiled from source** with Ada support (`--enable-libghdl
  --enable-synth`), requiring **GNAT (Ada compiler)**.
- The resulting `ghdl.so` plugin has a **runtime dependency on `libghdl-*.so`**,
  which in turn links to Ada runtime libraries (`libgnat`, `libgnarl`).  These
  must all be bundled and their rpaths adjusted for the portable release.
- Build time is significant: GHDL from source with GNAT takes ~20–30 min in CI.
- The Makefile-based plugin build is simple once GHDL is available; the
  complexity is entirely in building and bundling GHDL portably.

### Feasibility assessment

`manylinux_2_34` is based on AlmaLinux 8, which ships `gcc-gnat` in its
AppStream/PowerTools repos.  The GHDL project's own CI builds from source on
Ubuntu 22.04 with `gnat`.  Equivalent steps should work in the container with:

```sh
dnf install -y gcc-gnat
```

However, `gcc-gnat` in AlmaLinux 8 is GCC 8-based GNAT, which is sufficient
(GHDL requires GNAT ≥ 8).  There is a risk that Ada runtime libraries from
GCC 8 don't coexist cleanly with GCC 14-compiled C++ objects; this needs
validation.

An alternative is to use **pre-built GHDL binaries** from the GHDL GitHub
Releases page (`ghdl-gha_ubuntu-22.04-x86_64.tgz`).  These are built on
Ubuntu 22.04 (glibc 2.35) which is newer than manylinux_2_34 (glibc 2.34), so
they should be binary-compatible.  Using pre-built GHDL would eliminate the
GNAT dependency and drastically reduce build time.

### Recommended approach

**Phase A — pre-built GHDL binaries (lower risk, faster):**

1. Download the latest GHDL release tarball for `linux-x86_64` from
   https://github.com/ghdl/ghdl/releases.
2. Extract into a staging directory, giving `GHDL` binary and `libghdl-*.so`.
3. Build the plugin:
   ```sh
   cd ${proj}/ghdl-yosys-plugin
   make GHDL=${staging}/bin/ghdl YOSYS_CONFIG=${release_dir}/bin/yosys-config
   ```
4. Bundle `ghdl.so` and `libghdl-*.so` into the release.
5. Patch the rpath of `ghdl.so` to point to `$ORIGIN/../lib/` (using `patchelf`,
   which is available in the manylinux image).

**Phase B — build GHDL from source (higher portability guarantee):**

If Phase A proves unreliable (e.g., because pre-built GHDL has glibc
assumptions that break), fall back to building from source:

```sh
dnf install -y gcc-gnat
git clone https://github.com/ghdl/ghdl
cd ghdl
./configure --enable-libghdl --enable-synth --prefix=${staging}
make all GNATMAKE="gnatmake -j$(nproc)"
make install
```

Then proceed as in Phase A for the plugin build and bundling step.

### Additional files needed in the release

```
lib/
  libghdl-<version>.so      # GHDL shared library
  libgnat-<gcc>.so           # Ada runtime (if building from source)
share/yosys/plugins/
  ghdl.so                    # The plugin itself
```

The `pyproject-release.toml` `package-data` section would need updating to
include `lib/*.so`.

### Open questions before committing to ghdl

1. Does `gcc-gnat` in AlmaLinux 8 produce libraries that are compatible with
   the GCC 14-compiled yosys objects? (Test in the container first.)
2. Are GHDL pre-built Linux binaries sufficiently portable for manylinux_2_34?
   (Check `ldd` output of pre-built `libghdl-*.so`.)
3. What is the acceptable increase in tarball size?  GHDL adds ~50–100 MB to
   the release.
4. Is GHDL synthesis mature enough for inclusion in a "stable" release tarball,
   given the README still says "experimental and work in progress"?

---

## Suggested implementation order

1. **Validate the yosys-slang build in the manylinux container** locally before
   touching CI.  Run the container, activate the gcc toolset, and confirm
   `slang.so` links and loads into yosys correctly.
2. **Add yosys-slang to `scripts/build.sh`** and push — it should be a
   low-risk change.
3. **Prototype ghdl-yosys-plugin** using pre-built GHDL binaries.  Confirm
   `ghdl.so` loads and a smoke test (`yosys -m ghdl.so -p 'help ghdl'`)
   passes before integrating into the release.
4. **Add ghdl-yosys-plugin** to `scripts/build.sh` once the prototype is solid.

---

## Changes to `pyproject-release.toml` / `pyproject.toml`

Both plugins are binary artefacts, not Python modules, so the pyproject changes
are limited to ensuring `package-data` globs pick them up:

```toml
[tool.setuptools.package-data]
# existing
"pyosys" = ["*.so", "yosys-abc", "share/**/*"]
# slang.so will already be captured by the yosys share/** glob above
# For ghdl, add lib/* if we bundle libghdl there:
"pyosys" = ["*.so", "yosys-abc", "share/**/*", "../lib/*.so"]
```

(Exact paths depend on final layout decisions.)

---

## Summary table

| Item | Complexity | Blocking issues | Recommendation |
|------|------------|-----------------|----------------|
| yosys-slang in release | Low | GCC toolset activation in container | **Do it now** |
| ghdl-yosys-plugin (pre-built GHDL) | Medium | glibc compatibility check | **Prototype first** |
| ghdl-yosys-plugin (from-source GHDL) | High | GNAT availability + Ada runtime bundling | **Fallback if needed** |
