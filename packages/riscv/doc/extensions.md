RISC-V extensions define optional architectural features that can be added to a base ISA to expand functionality, performance, or data-type support.
Each extension listed below is provided as a `RiscVExtension` constant that can be enabled when configuring a decoder, emulator, or microarchitecture implementation.

These constants encapsulate everything needed for an extension:
- Supported instructions
- Decoding rules
- Microcode sequences
- Privilege requirements
- Structural metadata

Use these extensions to compose the exact ISA profile your core supports-for example, `rvc + rv32M + rv32i`, or `rv32Atomics + rv64Atomics + rv64i + rv32i`.
Remember that each extension only implements the instructions for the bit size it references. To gain full support, add all variants which apply.
