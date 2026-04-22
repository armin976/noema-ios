// PythonExecutor.swift
import Foundation

/// Result of a Python execution
struct PythonExecutionResult: Codable, Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let executionTimeMs: Int
    let error: String?
    let timedOut: Bool
}

/// Protocol for platform-specific Python execution backends
protocol PythonExecutor: Sendable {
    func execute(code: String, timeout: TimeInterval) async throws -> PythonExecutionResult
    var isAvailable: Bool { get }
}

let pythonSandboxAllowedRootEnvVar = "NOEMA_PYTHON_ALLOWED_ROOT"

/// Sandbox preamble injected before user code to restrict dangerous operations
let pythonSandboxPreamble = """
import sys as _sys
import os as _os
import builtins as _builtins
import pathlib as _pathlib
import sysconfig as _sysconfig

# Block dangerous modules via meta_path hook
_blocked_modules = frozenset({
    'socket', 'subprocess', 'shutil', 'http', 'urllib',
    'requests', 'smtplib', 'ftplib', 'xmlrpc', 'multiprocessing',
    'ctypes', 'signal', 'webbrowser', 'antigravity',
})

class _SandboxImportBlocker:
    def find_spec(self, name, path=None, target=None):
        top = name.split('.')[0]
        if top in _blocked_modules:
            raise ImportError(f"Module '{name}' is blocked in sandbox mode")
        return None

    def find_module(self, name, path=None):
        top = name.split('.')[0]
        if top in _blocked_modules:
            raise ImportError(f"Module '{name}' is blocked in sandbox mode")
        return None

_noema_restore_callbacks = []
_noema_import_blocker = _SandboxImportBlocker()
_sys.meta_path.insert(0, _noema_import_blocker)

def _noema_register_restore(target, attr, original):
    _noema_restore_callbacks.append((target, attr, original))

def _noema_normalize_path(path):
    if isinstance(path, int):
        return None
    if hasattr(path, '__fspath__'):
        path = path.__fspath__()
    if not isinstance(path, str):
        return None
    if not _os.path.isabs(path):
        path = _os.path.join(_os.getcwd(), path)
    return _os.path.realpath(path)

def _noema_allowed_roots():
    roots = []
    try:
        if '__noema_allowed_root' in globals():
            roots.append(globals()['__noema_allowed_root'])
    except Exception:
        pass
    env_root = _os.environ.get('NOEMA_PYTHON_ALLOWED_ROOT')
    if env_root:
        roots.append(env_root)
    for key in ('stdlib', 'platstdlib'):
        try:
            location = _sysconfig.get_path(key)
        except Exception:
            location = None
        if location:
            roots.append(location)
    normalized = []
    for root in roots:
        if not root:
            continue
        normalized_root = _os.path.realpath(root)
        if normalized_root not in normalized:
            normalized.append(normalized_root)
    return normalized

def _noema_ensure_path_allowed(path):
    normalized = _noema_normalize_path(path)
    if normalized is None:
        return path

    for allowed_root in _noema_allowed_roots():
        if normalized == allowed_root or normalized.startswith(allowed_root + _os.sep):
            return path

    raise PermissionError(f"File system access outside the sandbox is blocked: {normalized}")

_noema_original_open = _builtins.open
def _noema_sandbox_open(file, *args, **kwargs):
    _noema_ensure_path_allowed(file)
    return _noema_original_open(file, *args, **kwargs)
_noema_register_restore(_builtins, 'open', _builtins.open)
_builtins.open = _noema_sandbox_open

def _blocked_call(*a, **k):
    raise PermissionError("This operation is blocked in sandbox mode")

for _attr in (
    'system', 'popen', 'execl', 'execle', 'execlp', 'execlpe',
    'execv', 'execve', 'execvp', 'execvpe', 'kill', 'killpg', 'fork'
):
    if hasattr(_os, _attr):
        _noema_register_restore(_os, _attr, getattr(_os, _attr))
        setattr(_os, _attr, _blocked_call)

if hasattr(_os, 'forkpty'):
    _noema_register_restore(_os, 'forkpty', _os.forkpty)
    _os.forkpty = _blocked_call

def _noema_wrap_path_function(name):
    if not hasattr(_os, name):
        return
    original = getattr(_os, name)
    def _wrapped(path, *args, **kwargs):
        _noema_ensure_path_allowed(path)
        return original(path, *args, **kwargs)
    _noema_register_restore(_os, name, original)
    setattr(_os, name, _wrapped)

def _noema_wrap_path_pair(name):
    if not hasattr(_os, name):
        return
    original = getattr(_os, name)
    def _wrapped(src, dst, *args, **kwargs):
        _noema_ensure_path_allowed(src)
        _noema_ensure_path_allowed(dst)
        return original(src, dst, *args, **kwargs)
    _noema_register_restore(_os, name, original)
    setattr(_os, name, _wrapped)

for _attr in ('remove', 'unlink', 'mkdir', 'makedirs', 'rmdir', 'listdir', 'scandir', 'stat', 'lstat'):
    _noema_wrap_path_function(_attr)
for _attr in ('rename', 'replace'):
    _noema_wrap_path_pair(_attr)

if hasattr(_os, 'walk'):
    _noema_original_walk = _os.walk
    def _noema_sandbox_walk(top, *args, **kwargs):
        _noema_ensure_path_allowed(top)
        return _noema_original_walk(top, *args, **kwargs)
    _noema_register_restore(_os, 'walk', _os.walk)
    _os.walk = _noema_sandbox_walk

_noema_path_methods = (
    'open', 'read_text', 'write_text', 'read_bytes', 'write_bytes',
    'mkdir', 'unlink', 'rename', 'replace', 'iterdir'
)

for _method_name in _noema_path_methods:
    if not hasattr(_pathlib.Path, _method_name):
        continue
    _original = getattr(_pathlib.Path, _method_name)
    def _make_wrapper(method):
        def _wrapped(self, *args, **kwargs):
            _noema_ensure_path_allowed(self)
            return method(self, *args, **kwargs)
        return _wrapped
    _noema_register_restore(_pathlib.Path, _method_name, _original)
    setattr(_pathlib.Path, _method_name, _make_wrapper(_original))

def _noema_restore_sandbox():
    while _noema_restore_callbacks:
        target, attr, original = _noema_restore_callbacks.pop()
        setattr(target, attr, original)
    try:
        _sys.meta_path.remove(_noema_import_blocker)
    except ValueError:
        pass

del _blocked_call
del _attr
del _method_name
del _original
del _make_wrapper
del _pathlib
del _builtins
del _sysconfig
del _blocked_modules
del _sys
del _os

"""
