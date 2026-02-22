#****************************************************************************
#* synth.py
#*
#* Copyright 2023-2025 Matthew Ballance and Contributors
#*
#* Licensed under the Apache License, Version 2.0 (the "License"); you may
#* not use this file except in compliance with the License.
#* You may obtain a copy of the License at:
#*
#*   http://www.apache.org/licenses/LICENSE-2.0
#*
#* Unless required by applicable law or agreed to in writing, software
#* distributed under the License is distributed on an "AS IS" BASIS,
#* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#* See the License for the specific language governing permissions and
#* limitations under the License.
#*
#****************************************************************************
import os
import logging
from typing import ClassVar, List, Tuple
from dv_flow.mgr import TaskDataResult, FileSet

_log = logging.getLogger("yosys.synth")


def _collect_rtl(input) -> Tuple[List[str], List[str], List[str]]:
    """Collect RTL source files, include dirs, and liberty libs from input filesets."""
    sources = []   # list of (path, is_sv) tuples
    incdirs = []
    liberty_files = []

    for fs in input.inputs:
        if fs.type != "std.FileSet":
            continue
        ft = fs.filetype
        if ft in ("verilogSource", "systemVerilogSource"):
            is_sv = (ft == "systemVerilogSource")
            for f in fs.files:
                sources.append((os.path.join(fs.basedir, f), is_sv))
            for d in fs.incdirs:
                incdirs.append(os.path.join(fs.basedir, d))
        elif ft == "verilogIncDir":
            if fs.basedir.strip():
                incdirs.append(fs.basedir)
        elif ft in ("verilogInclude", "systemVerilogInclude"):
            for d in fs.incdirs:
                incdirs.append(os.path.join(fs.basedir, d))
        elif ft == "libertyLib":
            for f in fs.files:
                liberty_files.append(os.path.join(fs.basedir, f))
            if not fs.files and fs.basedir.strip():
                liberty_files.append(fs.basedir)

    return sources, incdirs, liberty_files


def _write_read_cmds(fp, sources, incdirs):
    """Write yosys read_verilog commands for all sources."""
    for d in incdirs:
        fp.write(f"read_verilog -incdir {d}\n")
    for path, is_sv in sources:
        flag = " -sv" if is_sv else ""
        fp.write(f"read_verilog{flag} {path}\n")


async def Synth(ctxt, input) -> TaskDataResult:
    """Generic technology-independent RTL synthesis."""
    sources, incdirs, liberty_files = _collect_rtl(input)

    top = input.params.top
    output_format = input.params.output_format or "json"
    flatten = input.params.flatten
    nofsm = input.params.nofsm
    noabc = input.params.noabc
    retime = input.params.retime
    extra_args = list(input.params.args or [])

    out_file = f"netlist.{output_format}"
    script_path = os.path.join(input.rundir, "synth.ys")

    with open(script_path, "w") as fp:
        _write_read_cmds(fp, sources, incdirs)

        for lib in liberty_files:
            fp.write(f"read_liberty -lib {lib}\n")

        synth_cmd = "synth"
        if top:
            synth_cmd += f" -top {top}"
        if flatten:
            synth_cmd += " -flatten"
        if nofsm:
            synth_cmd += " -nofsm"
        if noabc:
            synth_cmd += " -noabc"
        if retime:
            synth_cmd += " -retime"
        fp.write(synth_cmd + "\n")

        if liberty_files:
            fp.write(f"dfflibmap -liberty {liberty_files[0]}\n")
            fp.write(f"abc -liberty {liberty_files[0]}\n")

        fp.write("opt_clean\n")

        if liberty_files:
            fp.write(f"stat -liberty {liberty_files[0]}\n")
        else:
            fp.write("stat\n")

        out_path = os.path.join(input.rundir, out_file)
        if output_format == "json":
            fp.write(f"write_json {out_path}\n")
        elif output_format == "verilog":
            fp.write(f"write_verilog {out_path}\n")
        elif output_format == "blif":
            fp.write(f"write_blif {out_path}\n")
        elif output_format == "edif":
            fp.write(f"write_edif {out_path}\n")
        elif output_format == "rtlil":
            fp.write(f"write_rtlil {out_path}\n")

        for arg in extra_args:
            fp.write(arg + "\n")

    cmd = ["yosys", "-l", "synth.log", script_path]
    status = await ctxt.exec(cmd, logfile="synth.log")

    output = []
    if status == 0 and os.path.isfile(out_path):
        output.append(FileSet(
            src=input.name,
            filetype="yosysNetlist",
            basedir=input.rundir,
            files=[out_file],
            attributes=[f"format={output_format}"] + ([f"top={top}"] if top else []),
        ))

    return TaskDataResult(status=status, output=output)


async def SynthIce40(ctxt, input) -> TaskDataResult:
    """Synthesis targeting Lattice iCE40 FPGAs."""
    sources, incdirs, _ = _collect_rtl(input)

    top = input.params.top
    device = input.params.device or "hx"
    output_format = input.params.output_format or "json"
    dff = input.params.dff
    retime = input.params.retime
    nocarry = input.params.nocarry
    nobram = input.params.nobram
    dsp = input.params.dsp
    abc9 = input.params.abc9
    extra_args = list(input.params.args or [])

    out_file = f"netlist.{output_format}"
    script_path = os.path.join(input.rundir, "synth.ys")

    with open(script_path, "w") as fp:
        _write_read_cmds(fp, sources, incdirs)

        out_path = os.path.join(input.rundir, out_file)
        synth_cmd = f"synth_ice40 -device {device}"
        if top:
            synth_cmd += f" -top {top}"
        if dff:
            synth_cmd += " -dff"
        if retime:
            synth_cmd += " -retime"
        if nocarry:
            synth_cmd += " -nocarry"
        if nobram:
            synth_cmd += " -nobram"
        if dsp:
            synth_cmd += " -dsp"
        if abc9:
            synth_cmd += " -abc9"
        if output_format == "json":
            synth_cmd += f" -json {out_path}"
        elif output_format == "blif":
            synth_cmd += f" -blif {out_path}"
        elif output_format == "edif":
            synth_cmd += f" -edif {out_path}"
        fp.write(synth_cmd + "\n")

        for arg in extra_args:
            fp.write(arg + "\n")

    cmd = ["yosys", "-l", "synth.log", script_path]
    status = await ctxt.exec(cmd, logfile="synth.log")

    output = []
    if status == 0 and os.path.isfile(out_path):
        output.append(FileSet(
            src=input.name,
            filetype="yosysNetlist",
            basedir=input.rundir,
            files=[out_file],
            attributes=[f"format={output_format}", "target=ice40", f"device={device}"]
                       + ([f"top={top}"] if top else []),
        ))

    return TaskDataResult(status=status, output=output)


async def SynthXilinx(ctxt, input) -> TaskDataResult:
    """Synthesis targeting Xilinx FPGAs."""
    sources, incdirs, _ = _collect_rtl(input)

    top = input.params.top
    family = input.params.family or "xc7"
    output_format = input.params.output_format or "json"
    flatten = input.params.flatten
    dff = input.params.dff
    retime = input.params.retime
    nobram = input.params.nobram
    nodsp = input.params.nodsp
    noiopad = input.params.noiopad
    noclkbuf = input.params.noclkbuf
    abc9 = input.params.abc9
    extra_args = list(input.params.args or [])

    out_file = f"netlist.{output_format}"
    script_path = os.path.join(input.rundir, "synth.ys")

    with open(script_path, "w") as fp:
        _write_read_cmds(fp, sources, incdirs)

        out_path = os.path.join(input.rundir, out_file)
        synth_cmd = f"synth_xilinx -family {family}"
        if top:
            synth_cmd += f" -top {top}"
        if flatten:
            synth_cmd += " -flatten"
        if dff:
            synth_cmd += " -dff"
        if retime:
            synth_cmd += " -retime"
        if nobram:
            synth_cmd += " -nobram"
        if nodsp:
            synth_cmd += " -nodsp"
        if noiopad:
            synth_cmd += " -noiopad"
        if noclkbuf:
            synth_cmd += " -noclkbuf"
        if abc9:
            synth_cmd += " -abc9"
        if output_format == "json":
            synth_cmd += f" -json {out_path}"
        elif output_format == "edif":
            synth_cmd += f" -edif {out_path}"
        elif output_format == "blif":
            synth_cmd += f" -blif {out_path}"
        fp.write(synth_cmd + "\n")

        for arg in extra_args:
            fp.write(arg + "\n")

    cmd = ["yosys", "-l", "synth.log", script_path]
    status = await ctxt.exec(cmd, logfile="synth.log")

    output = []
    if status == 0 and os.path.isfile(out_path):
        output.append(FileSet(
            src=input.name,
            filetype="yosysNetlist",
            basedir=input.rundir,
            files=[out_file],
            attributes=[f"format={output_format}", "target=xilinx", f"family={family}"]
                       + ([f"top={top}"] if top else []),
        ))

    return TaskDataResult(status=status, output=output)


async def SynthLattice(ctxt, input) -> TaskDataResult:
    """Synthesis targeting Lattice FPGAs (ECP5, MachXO2/3, CrossLink-NX, Certus-NX)."""
    sources, incdirs, _ = _collect_rtl(input)

    top = input.params.top
    family = input.params.family or "ecp5"
    output_format = input.params.output_format or "json"
    dff = input.params.dff
    retime = input.params.retime
    extra_args = list(input.params.args or [])

    out_file = f"netlist.{output_format}"
    script_path = os.path.join(input.rundir, "synth.ys")

    with open(script_path, "w") as fp:
        _write_read_cmds(fp, sources, incdirs)

        out_path = os.path.join(input.rundir, out_file)
        synth_cmd = f"synth_lattice -family {family}"
        if top:
            synth_cmd += f" -top {top}"
        if dff:
            synth_cmd += " -dff"
        if retime:
            synth_cmd += " -retime"
        if output_format == "json":
            synth_cmd += f" -json {out_path}"
        elif output_format == "edif":
            synth_cmd += f" -edif {out_path}"
        fp.write(synth_cmd + "\n")

        for arg in extra_args:
            fp.write(arg + "\n")

    cmd = ["yosys", "-l", "synth.log", script_path]
    status = await ctxt.exec(cmd, logfile="synth.log")

    output = []
    if status == 0 and os.path.isfile(out_path):
        output.append(FileSet(
            src=input.name,
            filetype="yosysNetlist",
            basedir=input.rundir,
            files=[out_file],
            attributes=[f"format={output_format}", "target=lattice", f"family={family}"]
                       + ([f"top={top}"] if top else []),
        ))

    return TaskDataResult(status=status, output=output)


async def SynthGowin(ctxt, input) -> TaskDataResult:
    """Synthesis targeting Gowin FPGAs."""
    sources, incdirs, _ = _collect_rtl(input)

    top = input.params.top
    output_format = input.params.output_format or "json"
    extra_args = list(input.params.args or [])

    out_file = f"netlist.{output_format}"
    script_path = os.path.join(input.rundir, "synth.ys")

    with open(script_path, "w") as fp:
        _write_read_cmds(fp, sources, incdirs)

        out_path = os.path.join(input.rundir, out_file)
        synth_cmd = "synth_gowin"
        if top:
            synth_cmd += f" -top {top}"
        if output_format == "json":
            synth_cmd += f" -json {out_path}"
        elif output_format == "verilog":
            synth_cmd += f" -vout {out_path}"
        fp.write(synth_cmd + "\n")

        for arg in extra_args:
            fp.write(arg + "\n")

    cmd = ["yosys", "-l", "synth.log", script_path]
    status = await ctxt.exec(cmd, logfile="synth.log")

    output = []
    if status == 0 and os.path.isfile(out_path):
        output.append(FileSet(
            src=input.name,
            filetype="yosysNetlist",
            basedir=input.rundir,
            files=[out_file],
            attributes=[f"format={output_format}", "target=gowin"]
                       + ([f"top={top}"] if top else []),
        ))

    return TaskDataResult(status=status, output=output)


async def FormalPrepare(ctxt, input) -> TaskDataResult:
    """Prepare an RTL design for formal verification, emitting an SMT2 model."""
    sources, incdirs, _ = _collect_rtl(input)

    top = input.params.top
    bv = input.params.bv
    mem = input.params.mem
    wires = input.params.wires
    extra_args = list(input.params.args or [])

    out_file = "model.smt2"
    script_path = os.path.join(input.rundir, "formal.ys")

    with open(script_path, "w") as fp:
        # Use -formal flag so formal-only constructs are enabled
        for d in incdirs:
            fp.write(f"read_verilog -incdir {d}\n")
        for path, is_sv in sources:
            flag = " -sv" if is_sv else ""
            fp.write(f"read_verilog -formal{flag} {path}\n")

        if top:
            fp.write(f"hierarchy -top {top}\n")
        else:
            fp.write("hierarchy -auto-top\n")

        fp.write("proc\n")
        fp.write("opt\n")
        fp.write("memory -nordff -nomap\n")
        fp.write("opt -fast\n")

        out_path = os.path.join(input.rundir, out_file)
        smt2_cmd = f"write_smt2"
        if bv:
            smt2_cmd += " -bv"
        if mem:
            smt2_cmd += " -mem"
        if wires:
            smt2_cmd += " -wires"
        fp.write(f"{smt2_cmd} {out_path}\n")

        for arg in extra_args:
            fp.write(arg + "\n")

    cmd = ["yosys", "-l", "formal.log", script_path]
    status = await ctxt.exec(cmd, logfile="formal.log")

    output = []
    if status == 0 and os.path.isfile(out_path):
        output.append(FileSet(
            src=input.name,
            filetype="yosysSMT2",
            basedir=input.rundir,
            files=[out_file],
            attributes=[f"top={top}"] if top else [],
        ))

    return TaskDataResult(status=status, output=output)


async def Script(ctxt, input) -> TaskDataResult:
    """Run an arbitrary yosys script, consuming RTL sources."""
    sources, incdirs, liberty_files = _collect_rtl(input)

    script_content = input.params.script
    extra_read_rtl = input.params.read_rtl
    output_format = input.params.output_format or ""
    top = input.params.top

    script_path = os.path.join(input.rundir, "user.ys")

    with open(script_path, "w") as fp:
        if extra_read_rtl:
            _write_read_cmds(fp, sources, incdirs)
            for lib in liberty_files:
                fp.write(f"read_liberty -lib {lib}\n")
        fp.write(script_content + "\n")

    cmd = ["yosys", "-l", "script.log", script_path]
    status = await ctxt.exec(cmd, logfile="script.log")

    output = []
    if status == 0 and output_format:
        out_file = f"netlist.{output_format}"
        out_path = os.path.join(input.rundir, out_file)
        if os.path.isfile(out_path):
            output.append(FileSet(
                src=input.name,
                filetype="yosysNetlist",
                basedir=input.rundir,
                files=[out_file],
                attributes=[f"format={output_format}"] + ([f"top={top}"] if top else []),
            ))

    return TaskDataResult(status=status, output=output)
