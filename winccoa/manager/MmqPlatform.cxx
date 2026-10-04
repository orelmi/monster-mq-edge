#include "MmqPlatform.hxx"

#include <filesystem>
#include <system_error>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <mmsystem.h>
#else
#include <csignal>
#include <cstring>
#endif

namespace mmq
{

static void (*stopHandler)() = nullptr;

#ifdef _WIN32

void saveRuntimeSignals() {}
void restoreRuntimeSignals() {}
void addOnStackToHandlers() {}

// Runs on a thread the system creates for the event. Other events (console
// close, logoff, shutdown) keep their default handling.
static BOOL WINAPI onConsoleControl(DWORD type)
{
  if (type != CTRL_C_EVENT && type != CTRL_BREAK_EVENT)
    return FALSE;
  if (stopHandler)
    stopHandler();
  return TRUE;
}

void installStopHandler(void (*onStop)())
{
  stopHandler = onStop;
  // The most recently added handler is called first.
  SetConsoleCtrlHandler(onConsoleControl, FALSE);
  SetConsoleCtrlHandler(onConsoleControl, TRUE);
}

static std::filesystem::path fromUtf8(const std::string &s)
{
  if (s.empty())
    return std::filesystem::path();
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
  std::wstring w(n > 0 ? n : 0, L'\0');
  if (n > 0)
    MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), &w[0], n);
  return std::filesystem::path(w);
}

void raiseTimerResolution()
{
  timeBeginPeriod(1);
}

#else

static const int runtimeSignals[] = {SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGURG, SIGPROF};
static struct sigaction goHandlers[sizeof(runtimeSignals) / sizeof(runtimeSignals[0])];

void saveRuntimeSignals()
{
  for (size_t i = 0; i < sizeof(runtimeSignals) / sizeof(runtimeSignals[0]); i++)
    sigaction(runtimeSignals[i], nullptr, &goHandlers[i]);
}

void restoreRuntimeSignals()
{
  for (size_t i = 0; i < sizeof(runtimeSignals) / sizeof(runtimeSignals[0]); i++)
  {
    struct sigaction cur;
    if (sigaction(runtimeSignals[i], nullptr, &cur) != 0)
      continue;
    if (cur.sa_handler != goHandlers[i].sa_handler)
      sigaction(runtimeSignals[i], &goHandlers[i], nullptr);
  }
}

void addOnStackToHandlers()
{
  for (int sig = 1; sig < NSIG; sig++)
  {
    struct sigaction sa;
    if (sigaction(sig, nullptr, &sa) != 0)
      continue;
    if (sa.sa_handler == SIG_DFL || sa.sa_handler == SIG_IGN || (sa.sa_flags & SA_ONSTACK))
      continue;
    sa.sa_flags |= SA_ONSTACK;
    sigaction(sig, &sa, nullptr);
  }
}

static void onStopSignal(int)
{
  if (stopHandler)
    stopHandler();
}

// SA_ONSTACK because the signal may arrive on a Go runtime thread.
void installStopHandler(void (*onStop)())
{
  stopHandler = onStop;
  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_handler = onStopSignal;
  sa.sa_flags = SA_ONSTACK | SA_RESTART;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGINT, &sa, nullptr);
  sigaction(SIGTERM, &sa, nullptr);
}

static std::filesystem::path fromUtf8(const std::string &s)
{
  return std::filesystem::path(s);
}

void raiseTimerResolution() {}

#endif

std::string changeDirectory(const std::string &dir)
{
  std::error_code ec;
  std::filesystem::current_path(fromUtf8(dir), ec);
  return ec ? ec.message() : std::string();
}

bool isAbsolutePath(const std::string &path)
{
#ifdef _WIN32
  auto sep = [](char c) { return c == '\\' || c == '/'; };
  if (path.size() >= 2 && sep(path[0]) && sep(path[1]))
    return true;
  return path.size() >= 3 && ((path[0] >= 'A' && path[0] <= 'Z') || (path[0] >= 'a' && path[0] <= 'z')) && path[1] == ':' &&
         sep(path[2]);
#else
  return !path.empty() && path[0] == '/';
#endif
}

}  // namespace mmq
