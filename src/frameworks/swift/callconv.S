/* Calls from C into compiled Swift code that uses the Swift calling
 * convention's `self` register.
 *
 * Heap object destroyers (metadata[-2]: class deallocating deinits, closure
 * context and box destroyers) and class ivar destroyers take the object as
 * `self`, in r13, not in rdi. gcc cannot emit swiftcall, hence this thunk.
 * The object is passed in rdi as well, so destroyers written in C (ours,
 * for runtime-allocated boxes) work through the same path. r13 is
 * callee-saved in the C convention and is restored here. */
	.text

/* void sw_call_with_self(void (*fn)(void), void *self) */
	.globl sw_call_with_self
	.hidden sw_call_with_self
	.type sw_call_with_self, @function
sw_call_with_self:
	pushq %rbp
	movq %rsp, %rbp
	pushq %r13
	subq $8, %rsp
	movq %rdi, %r11
	movq %rsi, %r13
	movq %rsi, %rdi
	callq *%r11
	addq $8, %rsp
	popq %r13
	popq %rbp
	retq
	.size sw_call_with_self, .-sw_call_with_self

	.section .note.GNU-stack,"",@progbits
