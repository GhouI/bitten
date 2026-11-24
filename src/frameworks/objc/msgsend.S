/* Objective-C message dispatch for x86-64.
 *
 * Fast path: probe the receiver class's method cache and jump to the
 * implementation with every argument register untouched. Slow path: save
 * the argument registers, ask the C runtime for the implementation (which
 * may also replace the receiver, for forwarding targets), restore, jump.
 *
 * Cache layout (objc_internal.h): 0: mask, 8: count, 16: entries of
 * {sel, imp}; after the last entry a sentinel {1, cache} wraps the probe.
 * Only r10 and r11 are free: rax carries the vector-register count for
 * variadic callers. */
	.text

/* in: r11 = class to search, \sel = selector register.
 * hit: jumps to the implementation. miss: falls through, r11 = class. */
.macro CACHE_LOOKUP sel
	pushq %r11
	movq 16(%r11), %r10
	movq \sel, %r11
	shrq $4, %r11
	andq (%r10), %r11
	shlq $4, %r11
	addq %r10, %r11
1:	cmpq 16(%r11), \sel
	jne 2f
	movq 24(%r11), %r11
	addq $8, %rsp
	jmp *%r11
2:	cmpq $0, 16(%r11)
	je 4f
	cmpq $1, 16(%r11)
	jne 3f
	movq 24(%r11), %r11
	jmp 1b
3:	addq $16, %r11
	jmp 1b
4:	popq %r11
.endm

/* Slow path. \recv and \sel name the registers holding receiver and
 * selector; \stret is 1 for the struct-return convention. */
.macro SLOW_PATH recv, recv_off, sel, stret
	pushq %rbp
	movq %rsp, %rbp
	subq $0xc0, %rsp
	movq %rdi, 0x00(%rsp)
	movq %rsi, 0x08(%rsp)
	movq %rdx, 0x10(%rsp)
	movq %rcx, 0x18(%rsp)
	movq %r8, 0x20(%rsp)
	movq %r9, 0x28(%rsp)
	movq %rax, 0x30(%rsp)
	movdqa %xmm0, 0x40(%rsp)
	movdqa %xmm1, 0x50(%rsp)
	movdqa %xmm2, 0x60(%rsp)
	movdqa %xmm3, 0x70(%rsp)
	movdqa %xmm4, 0x80(%rsp)
	movdqa %xmm5, 0x90(%rsp)
	movdqa %xmm6, 0xa0(%rsp)
	movdqa %xmm7, 0xb0(%rsp)
	movq \sel, %rsi
	leaq \recv_off(%rsp), %rdi   /* address of the saved receiver */
	movq %r11, %rdx              /* class to search */
	movl $\stret, %ecx
	call dx_objc_lookup
	movq %rax, %r11
	movq 0x00(%rsp), %rdi
	movq 0x08(%rsp), %rsi
	movq 0x10(%rsp), %rdx
	movq 0x18(%rsp), %rcx
	movq 0x20(%rsp), %r8
	movq 0x28(%rsp), %r9
	movq 0x30(%rsp), %rax
	movdqa 0x40(%rsp), %xmm0
	movdqa 0x50(%rsp), %xmm1
	movdqa 0x60(%rsp), %xmm2
	movdqa 0x70(%rsp), %xmm3
	movdqa 0x80(%rsp), %xmm4
	movdqa 0x90(%rsp), %xmm5
	movdqa 0xa0(%rsp), %xmm6
	movdqa 0xb0(%rsp), %xmm7
	leave
	jmp *%r11
.endm

.macro ENTRY name
	.globl \name
	.type \name, @function
	.p2align 4
\name:
.endm

/* id objc_msgSend(id self, SEL _cmd, ...) */
ENTRY dx_objc_msgSend
	testq %rdi, %rdi
	je 9f
	testb $1, %dil
	jne 8f
	movq (%rdi), %r11
	CACHE_LOOKUP %rsi
8:	SLOW_PATH %rdi, 0x00, %rsi, 0
9:	xorl %eax, %eax
	xorl %edx, %edx
	xorps %xmm0, %xmm0
	xorps %xmm1, %xmm1
	ret

/* long double objc_msgSend_fpret(id self, SEL _cmd, ...) */
ENTRY dx_objc_msgSend_fpret
	testq %rdi, %rdi
	je 9f
	movq (%rdi), %r11
	CACHE_LOOKUP %rsi
	SLOW_PATH %rdi, 0x00, %rsi, 0
9:	fldz
	ret

/* _Complex long double objc_msgSend_fp2ret(id self, SEL _cmd, ...) */
ENTRY dx_objc_msgSend_fp2ret
	testq %rdi, %rdi
	je 9f
	movq (%rdi), %r11
	CACHE_LOOKUP %rsi
	SLOW_PATH %rdi, 0x00, %rsi, 0
9:	fldz
	fldz
	ret

/* void objc_msgSend_stret(void *out, id self, SEL _cmd, ...) */
ENTRY dx_objc_msgSend_stret
	testq %rsi, %rsi
	je 9f
	movq (%rsi), %r11
	CACHE_LOOKUP %rdx
	SLOW_PATH %rsi, 0x08, %rdx, 1
9:	movq %rdi, %rax
	ret

/* id objc_msgSendSuper(struct objc_super { id receiver; Class super_class; } *, SEL, ...) */
ENTRY dx_objc_msgSendSuper
	movq 8(%rdi), %r11
	movq (%rdi), %rdi
	CACHE_LOOKUP %rsi
	SLOW_PATH %rdi, 0x00, %rsi, 0

/* id objc_msgSendSuper2(struct { id receiver; Class current_class; } *, SEL, ...) */
ENTRY dx_objc_msgSendSuper2
	movq 8(%rdi), %r11
	movq 8(%r11), %r11       /* current_class->superclass */
	movq (%rdi), %rdi
	CACHE_LOOKUP %rsi
	SLOW_PATH %rdi, 0x00, %rsi, 0

ENTRY dx_objc_msgSendSuper_stret
	movq 8(%rsi), %r11
	movq (%rsi), %rsi
	CACHE_LOOKUP %rdx
	SLOW_PATH %rsi, 0x08, %rdx, 1

ENTRY dx_objc_msgSendSuper2_stret
	movq 8(%rsi), %r11
	movq 8(%r11), %r11
	movq (%rsi), %rsi
	CACHE_LOOKUP %rdx
	SLOW_PATH %rsi, 0x08, %rdx, 1

/* id method_invoke(id self, Method m, ...) */
ENTRY dx_method_invoke
	movq 16(%rsi), %r11
	movq (%rsi), %rsi
	jmp *%r11

/* void method_invoke_stret(void *out, id self, Method m, ...) */
ENTRY dx_method_invoke_stret
	movq 16(%rdx), %r11
	movq (%rdx), %rdx
	jmp *%r11

	.section .note.GNU-stack,"",@progbits
