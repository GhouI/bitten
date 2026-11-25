// The standard precedence groups and operator declarations. The compiler
// looks these names up in the Swift module; they carry no symbols.

precedencegroup AssignmentPrecedence {
  assignment: true
  associativity: right
}
precedencegroup FunctionArrowPrecedence {
  associativity: right
  higherThan: AssignmentPrecedence
}
precedencegroup TernaryPrecedence {
  associativity: right
  higherThan: FunctionArrowPrecedence
}
precedencegroup DefaultPrecedence {
  higherThan: TernaryPrecedence
}
precedencegroup LogicalDisjunctionPrecedence {
  associativity: left
  higherThan: TernaryPrecedence
}
precedencegroup LogicalConjunctionPrecedence {
  associativity: left
  higherThan: LogicalDisjunctionPrecedence
}
precedencegroup ComparisonPrecedence {
  higherThan: LogicalConjunctionPrecedence
}
precedencegroup NilCoalescingPrecedence {
  associativity: right
  higherThan: ComparisonPrecedence
}
precedencegroup CastingPrecedence {
  higherThan: NilCoalescingPrecedence
}
precedencegroup RangeFormationPrecedence {
  higherThan: CastingPrecedence
}
precedencegroup AdditionPrecedence {
  associativity: left
  higherThan: RangeFormationPrecedence
}
precedencegroup MultiplicationPrecedence {
  associativity: left
  higherThan: AdditionPrecedence
}
precedencegroup BitwiseShiftPrecedence {
  higherThan: MultiplicationPrecedence
}

postfix operator ++
postfix operator --
postfix operator ...
prefix operator ++
prefix operator --
prefix operator !
prefix operator ~
prefix operator +
prefix operator -
prefix operator ...
prefix operator ..<

infix operator << : BitwiseShiftPrecedence
infix operator &<< : BitwiseShiftPrecedence
infix operator >> : BitwiseShiftPrecedence
infix operator &>> : BitwiseShiftPrecedence
infix operator * : MultiplicationPrecedence
infix operator &* : MultiplicationPrecedence
infix operator / : MultiplicationPrecedence
infix operator % : MultiplicationPrecedence
infix operator & : MultiplicationPrecedence
infix operator + : AdditionPrecedence
infix operator &+ : AdditionPrecedence
infix operator - : AdditionPrecedence
infix operator &- : AdditionPrecedence
infix operator | : AdditionPrecedence
infix operator ^ : AdditionPrecedence
infix operator ... : RangeFormationPrecedence
infix operator ..< : RangeFormationPrecedence
infix operator ?? : NilCoalescingPrecedence
infix operator < : ComparisonPrecedence
infix operator <= : ComparisonPrecedence
infix operator > : ComparisonPrecedence
infix operator >= : ComparisonPrecedence
infix operator == : ComparisonPrecedence
infix operator != : ComparisonPrecedence
infix operator === : ComparisonPrecedence
infix operator !== : ComparisonPrecedence
infix operator ~= : ComparisonPrecedence
infix operator && : LogicalConjunctionPrecedence
infix operator || : LogicalDisjunctionPrecedence
infix operator *= : AssignmentPrecedence
infix operator &*= : AssignmentPrecedence
infix operator /= : AssignmentPrecedence
infix operator %= : AssignmentPrecedence
infix operator += : AssignmentPrecedence
infix operator &+= : AssignmentPrecedence
infix operator -= : AssignmentPrecedence
infix operator &-= : AssignmentPrecedence
infix operator <<= : AssignmentPrecedence
infix operator &<<= : AssignmentPrecedence
infix operator >>= : AssignmentPrecedence
infix operator &>>= : AssignmentPrecedence
infix operator &= : AssignmentPrecedence
infix operator ^= : AssignmentPrecedence
infix operator |= : AssignmentPrecedence
