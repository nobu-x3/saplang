rmdir /s /q build

mkdir build
mkdir "build\nightly"
mkdir "build\nightly\x86_64-windows"

"C:\Program Files\CMake\bin\cmake.EXE" -DCMAKE_BUILD_TYPE:STRING=Release -DCMAKE_EXPORT_COMPILE_COMMANDS:BOOL=TRUE -DCMAKE_C_COMPILER:FILEPATH="C:\Program Files\LLVM\bin\clang.exe" -DCMAKE_CXX_COMPILER:FILEPATH="C:\Program Files\LLVM\bin\clang++.exe" -DBUILD_TESTS=Off -DCMAKE_PREFIX_PATH="C:\Program Files\LLVM\cmake\modules\CMakeFiles" --no-warn-unused-cli -B build -G "Ninja"
"C:\Program Files\CMake\bin\cmake.EXE" --build build --config Release --target all

mkdir "build\nightly\x86_64-windows\Release"
move "build\bin\compiler.exe" "build\nightly\x86_64-windows\Release\saplangc.exe"