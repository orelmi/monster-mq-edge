// Process-level services of the manager that differ between Linux and
// Windows: Go runtime signal handlers, stop requests, working directory,
// timer resolution. Uses no WinCC OA header.
#ifndef MMQ_PLATFORM_HXX
#define MMQ_PLATFORM_HXX

#include <string>

namespace mmq
{

// Saves the Go runtime's handlers for the synchronous and runtime signals
// before WinCC OA installs its own (called first in main). The functions
// below that handle signals do nothing on Windows, where the Go runtime
// uses no signals (faults go through vectored exception handlers).
void saveRuntimeSignals();

// Reinstalls the saved Go handlers where WinCC OA replaced them, so Go
// runtime faults and preemption keep working inside the embedded library.
void restoreRuntimeSignals();

// Makes every installed handler run on the alternate signal stack, because
// a signal can arrive on a Go-owned thread with a small stack.
void addOnStackToHandlers();

// Calls onStop for an external stop request: SIGINT/SIGTERM, or Ctrl+C and
// Ctrl+Break on Windows. onStop runs in a signal handler or on a console
// control thread, so it may only set flags or end the process. Calling it
// again puts the handler back in front of handlers installed since.
void installStopHandler(void (*onStop)());

// Changes the working directory to a UTF-8 path; returns an error text,
// empty on success.
std::string changeDirectory(const std::string &dir);

// Whether a UTF-8 path is absolute (/..., or C:/... and \\server\... on Windows).
bool isAbsolutePath(const std::string &path);

// Raises the timer resolution to 1 ms for the rest of the process on
// Windows, where waits otherwise last at least 15.6 ms and dispatchMs would
// become the latency floor of Go -> WinCC OA requests.
void raiseTimerResolution();

}  // namespace mmq

#endif
