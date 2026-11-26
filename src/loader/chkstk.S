/* ___chkstk_darwin: the stack probe compilers emit before frames larger
 * than a page. On entry %rax holds the number of bytes about to be
 * allocated below the caller's %rsp; every page of that range is touched,
 * in order, so guard pages fault predictably. Every register is preserved.
 *
 * %rsp is lowered to each page before it is touched, so the probes are
 * never below the stack pointer: tools that grow the stack only for
 * accesses at or above it (valgrind) see an ordinary stack extension. */
    .text
    .globl dx_chkstk_darwin
    .type dx_chkstk_darwin, @function
dx_chkstk_darwin:
    push %rcx
    push %rax
    push %rdx
    mov %rsp, %rdx              /* to come back to */
    lea 32(%rsp), %rcx          /* the caller's %rsp: above our three pushes and the return address */
1:  cmp $0x1000, %rax
    jb 2f
    sub $0x1000, %rcx
    mov %rcx, %rsp
    orq $0, (%rsp)              /* touch the page */
    sub $0x1000, %rax
    jmp 1b
2:  sub %rax, %rcx
    mov %rcx, %rsp
    orq $0, (%rsp)
    mov %rdx, %rsp
    pop %rdx
    pop %rax
    pop %rcx
    ret
    .size dx_chkstk_darwin, .-dx_chkstk_darwin
    .section .note.GNU-stack,"",@progbits
