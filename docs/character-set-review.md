# CharacterSet review suggestion

The proposed Swift CharacterSet stores closed ranges of integer code points and compares those ranges directly. Unicode scalars skip U+D800 through U+DFFF. Two adjacent scalars at that boundary can therefore produce different representations depending on the initializer.

For example, build one set from the closed scalar range U+D7FF through U+E000 and another from a string containing those two scalars. Both sets have the same scalar members. The range initializer stores one interval, while the string initializer stores two. The proposed equality implementation compares interval counts and returns false.

Consider adding an equality regression test for these two constructions and canonicalizing ranges around the surrogate gap. Complement construction also needs the same convention so that a set containing every scalar has an empty inverse.
