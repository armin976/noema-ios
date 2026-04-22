#import <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

struct NoemaEmbeddedPythonInitResult {
    bool success;
    char *error_message;
};

struct NoemaEmbeddedPythonExecutionResult {
    bool success;
    char *json;
    char *error_message;
};

struct NoemaEmbeddedPythonInitResult noema_embedded_python_initialize(
    const char *runtime_root,
    const char *stdlib_path,
    const char *executable_path,
    bool use_system_logger
);

struct NoemaEmbeddedPythonExecutionResult noema_embedded_python_execute(
    const char *code,
    const char *sandbox_preamble,
    const char *temp_directory,
    double timeout_seconds
);

void noema_embedded_python_reset(void);
void noema_embedded_python_free_string(char *value);

#ifdef __cplusplus
}
#endif
