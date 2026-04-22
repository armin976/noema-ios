#include <cstring>

// Rename main() from upstream server so we can call it as a function
#define main llama_server_main

// Include the upstream HTTP server implementation copied into our package
// Path is relative to this file: Noema/NoemaLLamaServer/Sources/NoemaLLamaServer/bridge
#include "../upstream/tools/server/server.cpp"
