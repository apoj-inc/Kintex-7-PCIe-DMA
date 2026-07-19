import sys

from systemrdl import RDLCompiler, RDLCompileError
from peakrdl_regblock import RegblockExporter
from peakrdl_regblock.cpuif.apb4 import APB4_Cpuif
from peakrdl_regblock.udps import ALL_UDPS

input_files = [
    f"rdl/src/kdma.{sys.argv[1]}.rdl"
]

# Create an instance of the compiler
rdlc = RDLCompiler()

# Register all UDPs that 'regblock' requires
for udp in ALL_UDPS:
    rdlc.register_udp(udp)

try:
    # Compile your RDL files
    for input_file in input_files:
        rdlc.compile_file(input_file)

    # Elaborate the design
    root = rdlc.elaborate()
except RDLCompileError:
    # A compilation error occurred. Exit with error code
    sys.exit(1)

# Export a SystemVerilog implementation
exporter = RegblockExporter()
exporter.export(
    root, "rtl/gen",
    default_reset_activelow=True,
    default_reset_async=True,
    cpuif_cls=APB4_Cpuif
)