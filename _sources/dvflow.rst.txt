DV Flow Task Reference
======================

The ``dv_flow.libyosys`` package registers tasks under the ``yosys``
namespace for use in `DV Flow <https://dv-flow.github.io/>`_ ``flow.dv``
files.

File types
----------

``yosys.NetlistFile``
~~~~~~~~~~~~~~~~~~~~~

A synthesized netlist produced by Yosys.  Supported formats: JSON, Verilog
(``write_verilog``), BLIF, EDIF, or RTLIL.  This fileset type is produced by
the synthesis tasks below and consumed by downstream place-and-route tools.

``yosys.SMT2File``
~~~~~~~~~~~~~~~~~~

An SMT2 model produced by ``write_smt2``, for use with formal verification
back-ends such as ``smtbmc`` / SymbiYosys.

``yosys.LibertyLib``
~~~~~~~~~~~~~~~~~~~~

A Liberty ``.lib`` cell library consumed by technology-mapping passes
(``dfflibmap`` / ``abc``).  Pass one of these as an input to ``yosys.Synth``
to enable standard-cell mapping.

Synthesis tasks
---------------

.. _task-synth:

yosys.Synth
~~~~~~~~~~~

*Technology-independent RTL synthesis.*

Reads Verilog/SystemVerilog sources and runs the generic ``synth`` pass,
producing an optimised gate-level netlist.  When a Liberty cell library is
provided (via a ``yosys.LibertyLib`` fileset) ``dfflibmap`` and ``abc`` are
run automatically.

.. code-block:: yaml

   tasks:
     - name: rtl
       uses: std.FileSet
       with:
         type: systemVerilogSource
         include: "src/**/*.sv"

     - name: lib
       uses: std.FileSet
       with:
         type: libertyLib
         include: "tech/osu035_stdcells.lib"

     - name: synth
       uses: yosys.Synth
       needs: [rtl, lib]
       with:
         top: my_top
         output_format: verilog

**Parameters**

.. list-table::
   :header-rows: 1
   :widths: 20 10 70

   * - Name
     - Type
     - Description
   * - ``top``
     - str
     - Top-level module name (leave empty for auto-detect).
   * - ``output_format``
     - str
     - Output format: ``json`` (default), ``verilog``, ``blif``, ``edif``,
       ``rtlil``.
   * - ``flatten``
     - bool
     - Flatten the design before synthesis.
   * - ``nofsm``
     - bool
     - Disable FSM optimisation pass.
   * - ``noabc``
     - bool
     - Disable ABC logic optimisation (use Yosys built-in LUT mapper).
   * - ``retime``
     - bool
     - Enable flip-flop retiming via ABC.
   * - ``args``
     - list
     - Additional Yosys script lines appended verbatim after synthesis.

.. _task-synthice40:

yosys.SynthIce40
~~~~~~~~~~~~~~~~

*Synthesis targeting Lattice iCE40 FPGAs.*

Runs ``synth_ice40`` to produce an iCE40-optimised netlist.

.. code-block:: yaml

   - name: synth
     uses: yosys.SynthIce40
     needs: [rtl]
     with:
       top: blink
       family: hx
       output_format: json

**Parameters**

.. list-table::
   :header-rows: 1
   :widths: 20 10 70

   * - Name
     - Type
     - Description
   * - ``top``
     - str
     - Top-level module name.
   * - ``family``
     - str
     - iCE40 device family: ``hx`` (default), ``lp``, ``u``.
   * - ``output_format``
     - str
     - Output format: ``json`` (default), ``blif``, ``edif``.
   * - ``retime``
     - bool
     - Enable flip-flop retiming.
   * - ``abc9``
     - bool
     - Use the newer ABC9 flow (experimental).
   * - ``args``
     - list
     - Additional Yosys script lines appended verbatim.

.. _task-synthxilinx:

yosys.SynthXilinx
~~~~~~~~~~~~~~~~~

*Synthesis targeting Xilinx FPGAs (7-series, UltraScale, etc.)*

Runs ``synth_xilinx`` for the specified family.

.. code-block:: yaml

   - name: synth
     uses: yosys.SynthXilinx
     needs: [rtl]
     with:
       top: my_top
       family: xc7
       output_format: edif

**Parameters**

.. list-table::
   :header-rows: 1
   :widths: 20 10 70

   * - Name
     - Type
     - Description
   * - ``top``
     - str
     - Top-level module name.
   * - ``family``
     - str
     - Xilinx device family: ``xc7`` (default), ``xcup``, ``xcus``, ``xcu``.
   * - ``output_format``
     - str
     - Output format: ``json`` (default), ``edif``, ``blif``.
   * - ``flatten``
     - bool
     - Flatten design before synthesis.
   * - ``retime``
     - bool
     - Enable flip-flop retiming.
   * - ``nobram``
     - bool
     - Do not use block RAM cells.
   * - ``nodsp``
     - bool
     - Do not use DSP48* cells.
   * - ``args``
     - list
     - Additional Yosys script lines appended verbatim.

.. _task-synthlattice:

yosys.SynthLattice
~~~~~~~~~~~~~~~~~~

*Synthesis targeting Lattice FPGAs (ECP5, MachXO2/3, CrossLink-NX, Certus-NX).*

Runs ``synth_lattice`` for the specified device family.

Supported families: ``ecp5``, ``xo2``, ``xo3``, ``xo3d``, ``lifcl``, ``lfd2nx``.

.. code-block:: yaml

   - name: synth
     uses: yosys.SynthLattice
     needs: [rtl]
     with:
       top: my_top
       family: ecp5

**Parameters**

.. list-table::
   :header-rows: 1
   :widths: 20 10 70

   * - Name
     - Type
     - Description
   * - ``top``
     - str
     - Top-level module name.
   * - ``family``
     - str
     - Lattice device family (see supported list above).
   * - ``output_format``
     - str
     - Output format: ``json`` (default), ``blif``, ``edif``.
   * - ``args``
     - list
     - Additional Yosys script lines appended verbatim.

.. _task-synthgowin:

yosys.SynthGowin
~~~~~~~~~~~~~~~~

*Synthesis targeting Gowin FPGAs (experimental).*

Runs ``synth_gowin``.

.. code-block:: yaml

   - name: synth
     uses: yosys.SynthGowin
     needs: [rtl]
     with:
       top: my_top

**Parameters**

.. list-table::
   :header-rows: 1
   :widths: 20 10 70

   * - Name
     - Type
     - Description
   * - ``top``
     - str
     - Top-level module name.
   * - ``output_format``
     - str
     - Output format: ``json`` (default), ``blif``.
   * - ``args``
     - list
     - Additional Yosys script lines appended verbatim.

Formal verification
-------------------

.. _task-formalprepare:

yosys.FormalPrepare
~~~~~~~~~~~~~~~~~~~

*Prepare RTL for formal verification, producing an SMT2 model.*

Reads Verilog/SystemVerilog sources with the ``-formal`` flag (enabling SVA
constructs) and runs the standard formal preprocessing pipeline:
``hierarchy``, ``proc``, ``opt``, ``memory``, ``opt -fast``.  Emits an SMT2
model (``write_smt2``) for consumption by ``smtbmc`` / SymbiYosys.

.. code-block:: yaml

   - name: rtl
     uses: std.FileSet
     with:
       type: systemVerilogSource
       include: "src/**/*.sv"

   - name: prepare
     uses: yosys.FormalPrepare
     needs: [rtl]
     with:
       top: my_module

**Parameters**

.. list-table::
   :header-rows: 1
   :widths: 20 10 70

   * - Name
     - Type
     - Description
   * - ``top``
     - str
     - Top-level module name.
   * - ``args``
     - list
     - Additional Yosys script lines appended verbatim.

Utility tasks
-------------

yosys.Script
~~~~~~~~~~~~

*Run an arbitrary Yosys script, with optional automatic RTL loading.*

Executes a user-supplied Yosys script.  When ``read_rtl`` is ``true``, all
RTL sources from upstream filesets are read automatically before the script
runs.

.. code-block:: yaml

   - name: synth
     uses: yosys.Script
     needs: [rtl]
     with:
       script: "synth.ys"
       read_rtl: true

**Parameters**

.. list-table::
   :header-rows: 1
   :widths: 20 10 70

   * - Name
     - Type
     - Description
   * - ``script``
     - str
     - Path to the ``.ys`` script file to execute.
   * - ``read_rtl``
     - bool
     - Automatically read all upstream RTL sources before running the script.
   * - ``args``
     - list
     - Additional Yosys script lines appended verbatim after the script.
