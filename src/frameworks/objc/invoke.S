/* A generic System V x86-64 call, for NSInvocation (and anything else that
 * must call a function whose signature is known only at run time).
 *
 * void dx_objc_invoke(void (*fn)(void), const uint64_t gp[6], const double fp[8],
 *                     const uint64_t *stack, size_t nstack, uint64_t out[4])
 *
 * Loads the six integer argument registers and eight vector registers,
 * pushes `nstack` words of stack arguments (in order, lowest address
 * first), calls fn with al = 8 (for variadic callees), and stores rax, rdx,
 * xmm0 and xmm1 to out[0..3]. Callers place a hidden struct-return pointer
 * in gp[0] themselves. */
	.text
	.globl dx_objc_invoke_impl
	.hidden dx_objc_invoke_impl
	.type dx_objc_invoke_impl, @function
dx_objc_invoke_impl:
	pushq %rbp
	movq %rsp, %rbp
	pushq %rbx
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	subq $8, %rsp
	movq %rdi, %r12          /* fn */
	movq %rsi, %r13          /* gp */
	movq %rdx, %r14          /* fp */
	movq %r9, %r15           /* out */
	movq %r8, %rax           /* nstack, rounded up to keep rsp 16-aligned */
	shlq $3, %rax
	addq $15, %rax
	andq $-16, %rax
	subq %rax, %rsp
	xorq %r10, %r10
1:	cmpq %r8, %r10
	jae 2f
	movq (%rcx,%r10,8), %r11
	movq %r11, (%rsp,%r10,8)
	incq %r10
	jmp 1b
2:	movsd 0(%r14), %xmm0
	movsd 8(%r14), %xmm1
	movsd 16(%r14), %xmm2
	movsd 24(%r14), %xmm3
	movsd 32(%r14), %xmm4
	movsd 40(%r14), %xmm5
	movsd 48(%r14), %xmm6
	movsd 56(%r14), %xmm7
	movq 0(%r13), %rdi
	movq 8(%r13), %rsi
	movq 16(%r13), %rdx
	movq 24(%r13), %rcx
	movq 32(%r13), %r8
	movq 40(%r13), %r9
	movl $8, %eax
	callq *%r12
	movq %rax, 0(%r15)
	movq %rdx, 8(%r15)
	movsd %xmm0, 16(%r15)
	movsd %xmm1, 24(%r15)
	leaq -40(%rbp), %rsp
	popq %r15
	popq %r14
	popq %r13
	popq %r12
	popq %rbx
	popq %rbp
	retq
	.size dx_objc_invoke_impl, .-dx_objc_invoke_impl
	.section .note.GNU-stack,"",@progbits
