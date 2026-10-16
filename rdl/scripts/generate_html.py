import sys

from systemrdl import RDLCompiler, RDLCompileError
from peakrdl_html import HTMLExporter

input_files = []

for arg in sys.argv[1:]:
    input_files.append(f"rdl/src/kdma.{arg}.rdl")

# Create an instance of the compiler
rdlc = RDLCompiler()

try:
    for arg, input_file in zip(sys.argv[1:], input_files):
        rdlc.compile_file(input_file)

        root = rdlc.elaborate()

        exporter = HTMLExporter()
        exporter.export(root, f"rdl/doc/{arg}.html")
except RDLCompileError:
    # A compilation error occurred. Exit with error code
    sys.exit(1)
