
file(GLOB compiler_src CONFIGURE_DEPENDS "src/*.c")

add_executable(saplangc ${compiler_src})

llvm_map_components_to_libnames(llvm_libs core)

target_link_libraries(saplangc ${llvm_libs})

# if(BUILD_TESTS)
# 	add_library(saplang_lib STATIC ${compiler_src})
# 	include_directories(src)
# 	target_link_libraries(saplang_lib ${llvm_libs})
# endif(BUILD_TESTS)
