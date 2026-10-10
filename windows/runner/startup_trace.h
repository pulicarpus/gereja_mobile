#ifndef GKII_STARTUP_TRACE_H_
#define GKII_STARTUP_TRACE_H_
#include <windows.h>
#include <cstdio>
#include <cstring>
#include <cstdint>

// Diagnostic only: inactive unless the CI startup test supplies a trace path.
inline void GkiiStartupTrace(const char* label) {
  wchar_t path[32768];
  const DWORD size = GetEnvironmentVariableW(L"GKII_STARTUP_TRACE_PATH", path, 32768);
  if (size == 0 || size >= 32768) return;
  HANDLE file = CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
      nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD written;
  WriteFile(file, label, static_cast<DWORD>(std::strlen(label)), &written, nullptr);
  WriteFile(file, "\r\n", 2, &written, nullptr);
  CloseHandle(file);
}
inline void GkiiTraceAddress(const char* label, const void* address) {
  HMODULE module = nullptr;
  char path[MAX_PATH] = "unknown";
  GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
      GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
      reinterpret_cast<LPCSTR>(address), &module);
  if (module) GetModuleFileNameA(module, path, MAX_PATH);
  char line[MAX_PATH + 120];
  const auto offset = reinterpret_cast<std::uintptr_t>(address) -
      reinterpret_cast<std::uintptr_t>(module);
  std::snprintf(line, sizeof(line), "%s module=%s rva=0x%llx", label, path,
      static_cast<unsigned long long>(offset));
  GkiiStartupTrace(line);
}
inline LONG CALLBACK GkiiStartupException(EXCEPTION_POINTERS* info) {
  static thread_local bool tracing = false;
  if (tracing) return EXCEPTION_CONTINUE_SEARCH;
  const DWORD code = info->ExceptionRecord->ExceptionCode;
  if (code != EXCEPTION_ACCESS_VIOLATION && code != EXCEPTION_ILLEGAL_INSTRUCTION)
    return EXCEPTION_CONTINUE_SEARCH;
  tracing = true;
  char line[100];
  std::snprintf(line, sizeof(line), "native exception=0x%08lx", static_cast<unsigned long>(code));
  GkiiStartupTrace(line);
  GkiiTraceAddress("fault", info->ExceptionRecord->ExceptionAddress);
  void* frames[16];
  const USHORT count = CaptureStackBackTrace(0, 16, frames, nullptr);
  for (USHORT i = 0; i < count; ++i) GkiiTraceAddress("frame", frames[i]);
  tracing = false;
  return EXCEPTION_CONTINUE_SEARCH;
}
inline void GkiiEnableStartupDiagnostics() {
  if (GetEnvironmentVariableW(L"GKII_STARTUP_TRACE_PATH", nullptr, 0) > 0)
    AddVectoredExceptionHandler(1, GkiiStartupException);
}
#endif
