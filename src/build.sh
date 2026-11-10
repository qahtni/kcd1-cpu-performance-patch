#!/bin/bash
# Build KCDPerf.asi (x64, no C runtime). Needs mingw-w64.
# The image base is fixed: without it ld derives the base from the output path, so the binary would depend on where it is built.
set -eu
cd "$(dirname "$0")"
mkdir -p out
x86_64-w64-mingw32-gcc -O2 -s -Wall -Wextra -ffreestanding -fno-builtin -fno-stack-protector \
  -fno-asynchronous-unwind-tables -fno-tree-loop-distribute-patterns -fno-ident -mno-stack-arg-probe \
  -shared -nostdlib -nostartfiles -Wl,-e,DllMain -Wl,--dynamicbase,--nxcompat,--high-entropy-va \
  -Wl,--no-insert-timestamp -Wl,--image-base,0x2a8030000 -o out/KCDPerf.asi kcd_perf.c -lkernel32
ls -l out/KCDPerf.asi; sha256sum out/KCDPerf.asi
x86_64-w64-mingw32-objdump -p out/KCDPerf.asi | grep -E "DLL Name"
