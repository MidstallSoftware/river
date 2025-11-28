# River Core Design

The River RISC-V core is a 32-bit or 64-bit core with multiple "design profiles" ranging from nano to macro.
This allows for a wide variety of applications and a modular design.

## Profiles

- RC1.n - River Core v1 *nano*
    - RV32IC
    - 32-bit River Core
    - Intended for small FPGA like the iCESugar
    - Intended to run RTOS
    - Scalar
- RC1.mi - River Core v1 *micro*
    - RV32IMAC + Zicsr
    - Supervisor & user modes
    - 32-bit River Core
    - Intended to run Linux
    - Scalar
- RC1.s - River Core v1 *small*
    - RV64IMAC + Zicsr
    - Supervisor & user modes
    - 64-bit River Core
    - Intended to run Linux
    - Scalar
- RC1.f - River Core v1 *full*
    - RV64GC + Zicsr
    - Supervisor & user modes
    - 64-bit River Core
    - Intended to run Linux
    - Scalar
- RC1.ma - River Core v1 *macro*
    - RV64GC + Zicsr
    - Supervisor & user modes
    - 64-bit River Core
    - Intended to run Linux
    - Superscalar
