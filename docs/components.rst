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

dv-flow-libyosys
----------------

``dv-flow-libyosys`` (Python package ``dv_flow.libyosys``) integrates Yosys
with the `DV Flow <https://dv-flow.github.io/>`_ task framework.  It
provides ready-made synthesis and formal-preparation tasks that can be wired
into a larger EDA pipeline described in a ``flow.dv`` file.

See :doc:`dvflow` for the full task reference.
