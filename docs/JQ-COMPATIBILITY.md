## Intel macOS jq: file queries and extended libm

- The upstream jq 1.8.1 Mach-O reported its version but aborted before
  evaluating even a basic expression, at the unimplemented `pathconf`.
  `pathconf` and `fpathconf` translate Darwin POSIX selector values,
  preserve guest errno for indeterminate results, and report unsupported
  Darwin-only selectors with EINVAL.
- `fdopen$DARWIN_EXTSN` shares the stdio implementation, with translated
  errno on failure. Additional x86-64 libm exports include the gamma,
  Bessel, error, inverse hyperbolic, and floating-point helper functions
  imported by jq.
- Tests: `tests/c/files.c`, `tests/c/libm_ext.c`, and opt-in
  `tests/e2e/jq-macho.sh` with the unmodified upstream executable.
  jq imports: 22 missing -> 0. JSON stdin, file input, regular expression
  captures, and extended math run without stubs.
