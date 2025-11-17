# River Workspace

The River Workspace is where development happens for the River Core & SoC.
It is split into 3 main components; tooling, firmware, and HDL.

## Components

### Tools

The tools are written in Rust in order to gurantee memory safety with development.

### Firmware

The firmware is written in Zig, this is due to the lightweight nature of Zig.

### HDL

The HDL is written in Dart using Intel's ROHD (Rapid Open Hardware Development).
This contains the software simulator.
