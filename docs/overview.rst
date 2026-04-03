Overview
========

**yosys-bin** packages the `Yosys Open Synthesis Suite
<https://yosyshq.net/yosys/>`_ together with several companion tools and
Python integrations into a single manylinux-compatible release artefact.

Why yosys-bin?
--------------

Upstream Yosys releases are source-only. Building Yosys and its dependencies
from source requires a C++ toolchain, Tcl, readline, Python headers, and
several other libraries. yosys-bin provides ready-to-use binaries that:

* Run on any Linux system with glibc ≥ 2.34 (AlmaLinux 9+, Ubuntu 22.04+,
  Debian 12+, Fedora 37+, …).
* Include multi-version Python bindings (``pyosys``) compiled for Python
  3.10 – 3.13, selectable at runtime without rebuilding.
* Bundle the ``yosys-slang`` plugin for SystemVerilog elaboration via
  `LLVM/slang <https://sv-lang.com/>`_.
* Include the `Boolector <https://boolector.github.io/>`_ SMT solver for
  use with Yosys formal verification flows.
* Integrate with the `DV Flow <https://dv-flow.github.io/>`_ task framework
  via the ``dv-flow-libyosys`` package (``dv_flow.libyosys``).

Bundled components
------------------

.. list-table::
   :header-rows: 1
   :widths: 25 75

   * - Component
     - Description
   * - ``yosys``
     - Yosys Open Synthesis Suite binary and standard cell libraries
   * - ``pyosys``
     - Python 3.10–3.13 bindings for Yosys (``import pyosys``)
   * - ``yosys-slang`` plugin
     - SystemVerilog front-end plugin (``slang.so``) via ``read_slang``
   * - ``boolector``
     - Boolector SMT solver binary (used by ``write_smt2`` / ``smtbmc`` flows)
   * - ``dv-flow-libyosys``
     - DV Flow task library: ``yosys.Synth``, ``yosys.FormalPrepare``, etc.

Release naming
--------------

Releases track the upstream Yosys version tag, appended with the CI run ID
for traceability::

    yosys-bin-manylinux-x64-0.9.<run-id>.tar.gz

The embedded Python package version follows the same scheme (PEP 440 numeric
only, e.g. ``0.9.23403114660``).
