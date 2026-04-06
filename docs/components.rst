Components
==========

Yosys
-----

`Yosys <https://yosyshq.net/yosys/>`_ is an open-source RTL synthesis
framework.  It supports Verilog and SystemVerilog (via plugins), and can
target a wide range of FPGAs and ASICs through its standard cell technology
mapping flow.

The bundled ``yosys`` binary is built from the latest tagged upstream release
at the time the yosys-bin CI run executes.

Key binaries installed to ``bin/``::

    yosys         – main synthesis tool
    yosys-abc     – ABC logic synthesis engine (called by Yosys internally)
    yosys-config  – build-time configuration query tool

Standard cell libraries and scripts are installed under
``share/yosys/``.

pyosys — Python Bindings
-------------------------

``pyosys`` exposes the Yosys C++ API to Python using
`pybind11 <https://pybind11.readthedocs.io/>`_ bindings that are compiled
against the Yosys source tree.

yosys-bin provides separate ``.so`` files for each supported Python version
(3.10 – 3.13) so a single installation works with multiple interpreter
versions without recompilation::

    pyosys/libyosys.cpython-310-x86_64-linux-gnu.so
    pyosys/libyosys.cpython-311-x86_64-linux-gnu.so
    pyosys/libyosys.cpython-312-x86_64-linux-gnu.so
    pyosys/libyosys.cpython-313-x86_64-linux-gnu.so

The correct variant is selected automatically by the Python import machinery.

Basic usage::

    import pyosys

    d = pyosys.Design()
    d.run_pass("read_verilog -sv my_design.sv")
    d.run_pass("synth -top my_top")
    d.run_pass("write_json netlist.json")

yosys-slang Plugin
------------------

`yosys-slang <https://github.com/povik/yosys-slang>`_ is a Yosys frontend
plugin that uses the `slang <https://sv-lang.com/>`_ SystemVerilog compiler
library to elaborate SystemVerilog designs.  It provides the ``read_slang``
Yosys command, which supports a broader subset of the SystemVerilog standard
than the built-in ``read_verilog -sv`` parser.

The plugin is installed as::

    share/yosys/plugins/slang.so
    pyosys/share/yosys/plugins/slang.so   (for pip-installed paths)

Loading the plugin::

    # On the command line
    yosys -m slang

    # Inside a .ys script
    plugin -i slang
    read_slang top.sv
    synth -top top
    write_json netlist.json

The plugin is built from source during the yosys-bin CI run.  It statically
links ``slang`` and ``{fmt}`` so it has no additional runtime dependencies.

Boolector SMT Solver
--------------------

`Boolector <https://boolector.github.io/>`_ is an SMT solver for the theories
of fixed-size bit-vectors, arrays, and uninterpreted functions.  It is used by
Yosys formal verification flows to discharge proof obligations produced by
``write_smt2``.

The ``boolector`` binary is installed to ``bin/boolector``.

Typical usage with SymbiYosys / smtbmc::

    yosys -p "read_verilog -formal my_design.sv; \
               prep -top my_top; \
               write_smt2 -wires model.smt2"

    smtbmc --solver boolector model.smt2

Or use the DV Flow :ref:`FormalPrepare <task-formalprepare>` task to drive
the full flow from a ``flow.dv`` description.

sby — SymbiYosys
----------------

`SymbiYosys (sby) <https://yosyshq.net/sby/>`_ is a front-end driver for
Yosys-based formal hardware verification flows.  It reads a ``.sby``
configuration file that describes the design sources, the verification engine
to use (e.g. ``smtbmc``, ``aiger``, ``abc``), and the properties to check
(BMC, k-induction, cover), then orchestrates Yosys and the chosen solver.

Installed files::

    bin/sby
    share/yosys/python3/sby_*.py   – sby support library

Example ``.sby`` file::

    [options]
    mode bmc
    depth 20

    [engines]
    smtbmc boolector

    [script]
    read -formal my_design.sv
    prep -top my_top

    [files]
    my_design.sv

Run with::

    sby -f my_design.sby

mcy — Mutation Cover with Yosys
--------------------------------

`mcy <https://yosyshq.net/mcy/>`_ measures the quality of a formal
verification test suite by injecting mutations into a design and checking how
many are caught by the existing properties.  It produces a coverage report
showing which parts of the design are exercised by the formal tests.

Installed files::

    bin/mcy
    bin/mcy-dash
    share/mcy/scripts/   – helper scripts used internally by mcy
    share/mcy/dash/      – web dashboard assets for mcy-dash

Basic usage::

    mcy init          # create mcy.cfg template
    mcy run -j4       # run mutation checks with 4 parallel workers
    mcy dash          # start web dashboard on http://localhost:5000

eqy — Equivalence Check with Yosys
------------------------------------

`eqy <https://yosyshq.net/eqy/>`_ performs combinational and sequential
equivalence checking between two netlists using Yosys.  It is useful for
verifying that synthesis, retiming, or other transformations preserve circuit
behaviour.

Installed files::

    bin/eqy
    share/yosys/python3/eqy_job.py
    share/yosys/plugins/eqy_combine.so
    share/yosys/plugins/eqy_partition.so
    share/yosys/plugins/eqy_recode.so

Example ``.eqy`` file::

    [gold]
    read -sv gold.sv
    prep -top top

    [gate]
    read -sv gate.sv
    prep -top top

    [strategy simple]
    use sat
    depth 10

Run with::

    eqy -f my_check.eqy

dv-flow-libyosys
----------------

``dv-flow-libyosys`` (Python package ``dv_flow.libyosys``) integrates Yosys
with the `DV Flow <https://dv-flow.github.io/>`_ task framework.  It
provides ready-made synthesis and formal-preparation tasks that can be wired
into a larger EDA pipeline described in a ``flow.dv`` file.

See :doc:`dvflow` for the full task reference.
