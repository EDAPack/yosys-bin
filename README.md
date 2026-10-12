# yosys-bin

[Yosys](https://yosyshq.net/yosys/), the open RTL synthesis suite, as a portable pre-built package for [edapack](https://dvkit.org/edapack/). It includes multi-version Python bindings (`pyosys`), the `yosys-slang` SystemVerilog plugin and the Boolector SMT solver.

**Documentation:** https://dvkit.org/edapack/yosys-bin/

Releases, with one tarball per platform: https://github.com/EDAPack/yosys-bin/releases

Install it with [IVPM](https://github.com/fvutils/ivpm):

```yaml
- name: yosys-bin
  url: https://github.com/edapack/yosys-bin
  src: gh-rls
```
