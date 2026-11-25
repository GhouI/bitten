// Shared by every Swift test. The tests are built with -parse-stdlib, so
// there is no standard library: only Builtin types and the runtime.
precedencegroup AssignmentPrecedence { assignment: true associativity: right }
precedencegroup CastingPrecedence {}
