/* ___chkstk_darwin: the stack probe compilers emit before frames larger
 * than a page. On entry %rax holds the number of bytes about to be
 * allocated below the caller's %rsp; every page of that range is touched,
 * in order, so guard pages fault predictably. Every register is preserved. */
    .text
    .globl dx_chkstk_darwin
    .type dx_chkstk_darwin, @function
dx_chkstk_darwin:
    push %rcx
    push %rax
    lea 24(%rsp), %rcx          /* the caller's %rsp: above our two pushes and the return address */
1:  cmp $0x1000, %rax
    jb 2f
    sub $0x1000, %rcx
    orq $0, (%rcx)              /* touch the page */
    sub $0x1000, %rax
    jmp 1b
2:  sub %rax, %rcx
    orq $0, (%rcx)
    pop %rax
    pop %rcx
    ret
    .size dx_chkstk_darwin, .-dx_chkstk_darwin
    .section .note.GNU-stack,"",@progbits
