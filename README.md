[![Nightly Build and Release](https://github.com/nobu-x3/saplang/actions/workflows/nightly.yaml/badge.svg?branch=main)](https://github.com/nobu-x3/saplang/actions/workflows/nightly.yaml)
[![tests](https://github.com/nobu-x3/saplang/actions/workflows/tests.yaml/badge.svg?branch=main)](https://github.com/nobu-x3/saplang/actions/workflows/tests.yaml)

Please use the [Discord](https://discord.gg/8nqP7npDhV) to get in contact with me.
Check out the [wiki](https://github.com/nobu-x3/saplang/wiki) to get started with the language.

# Requirements
Pretty much the only requirement to be able to compile code using this compiler is having `clang v18.1.8` installed on your system. You might not need this exact version but it's the only one I'm actively testing on, so use other versions at your own risk.

# Installation
### Windows
* Unzip the nightly build somewhere on disk.
* Search up "Edit the system environment varibles."
* Click "Environment Variables...".
* Double click on the row that has "Path".
* Click "Browse" and find the executable that you unzipped.
* Re-login.

### Linux
* Untar the archive somewhere on $PATH.

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
