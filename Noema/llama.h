#pragma once

// Wrapper header to provide llama.cpp's public C API to the app target without the XCFramework.
// The implementation is linked via the embedded NoemaLLamaServer package.

#include "../External/NoemaLLamaServer/Sources/NoemaLLamaServer/upstream/include/llama.h"
