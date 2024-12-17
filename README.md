# !DISCLAIMER
This is not a C-KILLER. I have no aspirations for this language to become popular or even used by other people. I'm developing it for my own projects and according to my tastes and needs. USE AT YOUR OWN RISK!

# Goal
After coding in C and C++ for some time, I've come to the conclusion that both of the languages are not perfect. I've been searching and trying out different 'C/C++-killers' for a while but I still have not found a language that satisfies me. So I decided to build my own.
Saplang is built on top of the foundation that is C with some features inspired by C++. The end-goal is to have a language with the following features and qualities:
* Minimal syntactic differences to C.
* Full C-interop.
* 'defer' keyword.
* Modules.
* Build system written in Saplang.
* Comptime.
* *MAYBE!* Reflection as a language feature.

# Development
The compiler is currently in active Stage 1 development. Track progress [here](https://github.com/users/nobu-x3/projects/1). The goal here is to have a minimal compiler stripped of comptime, build system, *FULL* C-interop and **DEFINITELY** no standard library. This compiler, when stable, will be used to develop the Stage 2 compiler which aims to include everything mentioned and be feature complete. The users will only be required to build Stage 1 when building from source, otherwise they will use Stage 2.

# Personal Note
By no means am I proud of the C++ mess I created due to lack of foresight. Originally, I wanted to quickly get a dumbed-down stage 1 to make stage 2 ASAP but here I am half a year later with a couple core features still missing, pulling my hair out every time I have to debug...
Clearly a skill issue but it is what it is. There are so many @TODOs that beg for a refactor but I'm stuck between lack of enough time, depression and desire to pump out stage 1 asap. I sincerely apologize for anyone trying to read through this cursed codebase, I'll do better with stage 2.
