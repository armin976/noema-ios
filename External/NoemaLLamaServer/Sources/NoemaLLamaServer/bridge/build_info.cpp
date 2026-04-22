// Minimal definitions to satisfy upstream common/common.h externs.
// In CMake builds these come from a generated build-info.cpp.

extern "C" {
    int LLAMA_BUILD_NUMBER = 0;
    const char * LLAMA_COMMIT = "local";
    const char * LLAMA_COMPILER = "AppleClang (SPM)";
    const char * LLAMA_BUILD_TARGET = "apple";
}

