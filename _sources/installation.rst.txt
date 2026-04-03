Installation
============

From a GitHub Release tarball
------------------------------

Download the latest tarball from the
`GitHub Releases page <https://github.com/EDAPack/yosys-bin/releases>`_ and
install it with ``pip``::

    pip install yosys-bin-manylinux-x64-<version>.tar.gz

After installation the ``yosys`` binary will be available on ``PATH`` (via the
``bin/`` directory in the package) and the ``pyosys`` module will be importable::

    $ yosys --version
    Yosys 0.9.<run-id> ...

    $ python -c "import pyosys; print(pyosys.run_pass)"

The ``dv_flow.libyosys`` entry-point is registered automatically so DV Flow
can discover the Yosys synthesis tasks without any extra configuration.

With IVPM
---------

`IVPM <https://github.com/fvutils/ivpm>`_ users can declare a dependency
directly in their project's ``ivpm.yaml``::

    package:
      dep-sets:
        - name: default-dev
          deps:
            - name: yosys-bin
              src: gh-rls
              url: https://github.com/EDAPack/yosys-bin

Then run::

    ivpm update

IVPM will prepend the bundled ``bin/`` directory to ``PATH`` automatically
(see the ``env`` section of ``ivpm.yaml``).

Using pyosys
------------

``pyosys`` exposes the Yosys C++ API to Python via pybind11 bindings.  The
shared object is named with the CPython ABI tag so the correct variant is
loaded transparently::

    import pyosys

    d = pyosys.Design()
    d.run_pass("read_verilog -sv my_design.sv")
    d.run_pass("synth -top my_top")
    d.run_pass("write_json netlist.json")

Loading the yosys-slang plugin
------------------------------

The ``slang.so`` plugin is installed under ``share/yosys/plugins/`` in the
release tree.  Load it when invoking Yosys::

    yosys -m slang -p "read_slang my_design.sv; synth -top my_top"

Or place the following in a ``.yosys_plugins`` file in the working directory
or in ``~/.config/yosys/``::

    slang

System requirements
-------------------

* Linux x86-64 with **glibc ≥ 2.34** (manylinux_2_34).
* Python **3.10, 3.11, 3.12, or 3.13** for the ``pyosys`` bindings.
* No additional runtime libraries are required beyond the standard C/C++
  runtime — all dependencies are either statically linked or bundled.
