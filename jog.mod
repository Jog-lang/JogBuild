# jog-build, the build tool for Jog. The spec is notes/Packages.md.
#
# A module name is an identifier (notes/Packages.md, "Directives"), and
# `module jog-build` is rejected with "module name 'jog-build' is not an
# identifier". The module is jog_build; the program is still jog-build,
# built with -o out/jog-build.exe (see README.md).
module jog_build
version 0.1.0
kind executable
jog 0.0.1
