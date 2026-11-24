/* Thread-local variable thunk. Mach-O code calls the thunk stored in a TLV
 * descriptor with the descriptor in %rdi and expects the variable address
 * in %rax with every other register preserved. */
	.text
	.globl dx_tlv_get_addr
	.type dx_tlv_get_addr, @function
dx_tlv_get_addr:
	movq 8(%rdi), %rax
	movq %gs:0(,%rax,8), %rax
	testq %rax, %rax
	je 1f
	addq 16(%rdi), %rax
	ret
1:	pushq %rbp
	movq %rsp, %rbp
	andq $-64, %rsp
	subq $640, %rsp
	fxsave64 (%rsp)
	movq %rdi, 512(%rsp)
	movq %rsi, 520(%rsp)
	movq %rdx, 528(%rsp)
	movq %rcx, 536(%rsp)
	movq %r8, 544(%rsp)
	movq %r9, 552(%rsp)
	movq %r10, 560(%rsp)
	movq %r11, 568(%rsp)
	call dx_tlv_allocate
	fxrstor64 (%rsp)
	movq 512(%rsp), %rdi
	movq 520(%rsp), %rsi
	movq 528(%rsp), %rdx
	movq 536(%rsp), %rcx
	movq 544(%rsp), %r8
	movq 552(%rsp), %r9
	movq 560(%rsp), %r10
	movq 568(%rsp), %r11
	movq %rbp, %rsp
	popq %rbp
	addq 16(%rdi), %rax
	ret
	.size dx_tlv_get_addr, .-dx_tlv_get_addr
	.section .note.GNU-stack,"",@progbits
