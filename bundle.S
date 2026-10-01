/* The bundle the launcher carries. `bundle.tar.gz` is produced by the build
   just before this file is assembled; nothing binary is committed. */
    .section .rodata
    .balign 16
    .globl bundle_start
bundle_start:
    .incbin "bundle.tar.gz"
    .globl bundle_end
bundle_end:
    .byte 0
