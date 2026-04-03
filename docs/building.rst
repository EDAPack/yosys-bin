Building from Source
====================

yosys-bin is built inside a `manylinux_2_34
<https://github.com/pypa/manylinux>`_ Docker container so the resulting
binaries work on any Linux system with glibc ≥ 2.34.

Prerequisites
-------------

* Docker (any recent version)
* ``git`` with the repository cloned including submodules
* Network access (the build clones upstream repositories)

Build script
------------

The entire build is driven by ``scripts/build.sh``.  Run it manually via
Docker::

    docker run --rm \
        --volume "$(pwd):/io" \
        --workdir /io \
        quay.io/pypa/manylinux_2_34_x86_64 \
        /io/scripts/build.sh

The script performs the following steps in order:

1. **System dependencies** — installs build tools (``flex``, ``bison``,
   ``cmake``, ``readline-devel``, ``tcl-devel``, ``python3-devel``,
   ``glibc-static``, ``gcc-c++``) via ``dnf``.

2. **Yosys** — clones `YosysHQ/yosys <https://github.com/YosysHQ/yosys>`_
   (if not already present), applies patches to make
   ``libyosys.so`` version-agnostic, then builds with
   ``make ENABLE_PYOSYS=1``.

3. **Multi-version pyosys** — recompiles only the Python-binding object
   files for each of Python 3.10, 3.11, 3.12, and 3.13, producing a
   separate ``libyosys.cpython-3XX-*.so`` per version.

4. **yosys-slang plugin** — clones
   `povik/yosys-slang <https://github.com/povik/yosys-slang>`_, initialises
   its bundled ``slang`` and ``fmt`` submodules, and builds ``slang.so`` via
   CMake with ``-DBUILD_AS_PLUGIN=ON``.

5. **Boolector** — clones
   `Boolector/boolector <https://github.com/Boolector/boolector>`_ and
   builds the SMT solver binary.

6. **DV Flow integration** — copies ``src/dv_flow/libyosys/`` into the
   release tree and generates a release ``pyproject.toml`` with the
   computed version.

7. **Smoke tests** — runs the upstream Yosys Python test suite
   (``yosys/tests/pyosys/``) against each Python version to verify the
   multi-version bindings.

8. **Tarball** — packs the release directory into
   ``release/yosys-bin-manylinux-x64-<version>.tar.gz``.

Environment variables
---------------------

.. list-table::
   :header-rows: 1
   :widths: 25 75

   * - Variable
     - Description
   * - ``CI_BUILD``
     - Set to ``1`` to enable CI-specific steps (dnf install, etc.).  When
       unset the script assumes the required tools are already on ``PATH``.
   * - ``yosys_version``
     - Override the release version string (e.g. ``0.9.23000000001``).
       Defaults to ``1.0.0`` if unset.
   * - ``BUILD_NUM``
     - GitHub Actions run ID, appended to the version string for
       traceability.

CI / GitHub Actions
-------------------

The workflow in ``.github/workflows/ci.yml`` runs automatically on every
push and on a weekly schedule (Sunday 12:00 UTC).

Steps:

1. **check_is_needed** — queries the YosysHQ GitHub API for the latest
   Yosys release tag and constructs the build version string.
2. **build** — launches the Docker-based build described above.
3. **Create Release** — creates a GitHub Release with the version tag.
4. **Upload Files** — attaches the release tarball as a release asset.

Documentation is built separately and published to GitHub Pages whenever
``main`` is updated (see ``.github/workflows/docs.yml``).

Release layout
--------------

The unpacked release directory contains::

    bin/
      yosys
      yosys-abc
      yosys-config
      boolector
    lib/
    share/
      yosys/
        plugins/
          slang.so
        techlibs/
        …
    pyosys/
      libyosys.cpython-310-x86_64-linux-gnu.so
      libyosys.cpython-311-x86_64-linux-gnu.so
      libyosys.cpython-312-x86_64-linux-gnu.so
      libyosys.cpython-313-x86_64-linux-gnu.so
      yosys-abc
      share/yosys/plugins/slang.so
    dv_flow/
      libyosys/
        __init__.py
        __ext__.py
        synth.py
        flow.dv
        share/
    pyproject.toml
    ivpm.yaml
    LICENSE
