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

## Components

River's core is split into 3 central components which matches the primary stages of the pipeline.

1. Fetch Unit - Fetches instructions
2. Decode Unit - Decodes instructions
3. Execution Unit - Executes instructions

There are more components based on whether the In-Core Scaler is enabled, however those are the three base modules which River utilizes.

### Fetch Unit

River's fetch unit is very simple as to ensure the least amount of latency.
It simply reads a word length of memory or the L1 cache if present if RVC (RISC-V Compressed extension) is not enabled.

If the RVC extension is present, it reads the first half-word. Then it performs a mask check to ensure if it is a compressed instruction.
If the instruction is compressed, the fetch unit emits that into the IR (instruction register).
If the instruction is not compressed, the fetch unit will then read the other half-word of memory and combine the two.
The full instruction will then be loaded into IR.

### Decode Unit

River has 2 decode unit types; static & dynamic. The static decode unit reads the microcode at build time.
It then generates decode circuitry based on the instructions enabled in the extension set.
This circuitry is designed to operate without a clock pulse as to minimize the latency.

The dynamic decode unit is backed by one of the two microcode ROMs.
It utilizes the microcode lookup ROM, this is reponsible for turning operation
decode patterns into the microcode operation index & operation count.

A combination of either the static, dynamic, or both decode units may be present on a River core.
It is up to whoever is running the HDL generator to decide on how the microcode should be utilized.

### Execution Unit

Just like River's decode unit has 2 types, so does the execution unit.
Both the static & dynamic execution units are design with similar concepts.

The static decode unit takes the extension set at build time and contains circuitry for any instruction
which is going to be statically included. It reads the static decode unit's operation index but does not contain
an operation count. Instead, each micro-op is duplicated for every possible instruction that is statically included.
This ensures the circuitry is as simple as possible and has the least amount of latency.

The dynamic decode unit will read the second microcode ROM which is known as the operation ROM.
This contains a lookup table of all micro-operations which an instruction will utilize.
Each address in the operation ROM is split in based on the bit length required to fit all instructions.
The second component of the address to the operation ROM is the bit length of the sum total of the instruction
which the most amount of micro-ops. This allows the dynamic decoder to have simple circuitry to jump between instructions.

On each clock cycle, a micro-op is executed. However, there are two additional cycles. Before the first micro-op of an instruction,
the execution unit performs an initialization of the internal registers. This will clear the ALU register & fence
flag, it then initializes the field registers with the fields from the decoded registers. After the last micro-op of an instruction,
the last cycle is executed which sets the done flag. This signals the execution unit has completed.

### Microcode

To facilitate the use of a unified codebase, River's entire design is built on microcode. This means there are two ROMs for the microcode
to operate correctly. One is known as the lookup ROM, the other is known as the operations ROM. Each are crucial to perform micro-ops
and decode operations.

#### Fields

Micro-op fields are the different registers which are utilized and are not internal.
There are 6 fields in total, 4 of them are derived from the decode unit.

- `rd` - Register destination
- `rs1` - Register source 1
- `rs2` - Register source 2
- `imm` - Immediate value
- `pc` - Program counter
- `sp` - Stack pointer

Each of these fields can be overriden but will modify a register inside of the execution unit
and not the backing register. The `ModifyLatchMicroOp` can be utilized to reset a source back
to the value it had at the beginning of the operation. However, that only applies if it is a
field backed by the decoder unit. This means the `pc` and `sp` fields cannot have their states
restored as they are not latched.

#### Sources

Sources are similar to micro-op fields but include the internal registers.
If a source appears with the same name as a field, it is an alias to that field and thus
will hold the same values & have the same latching behavior.

- `alu` - ALU result
- `imm` - Immediate
- `rs1` - Register source 1
- `rs2` - Register source 2
- `sp` - Stack pointer
- `rd` - Register desination
- `pc` - Program counter
