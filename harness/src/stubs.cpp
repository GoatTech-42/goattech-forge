// Host stubs for symbols the real planner.cpp and temperature.cpp reference
// but the harness does not exercise (UI, serial, HAL). WIP: statics that need
// Marlin header types are still to be added; see syms list in the PR.
#include <cstddef>
#include <cstdint>

extern "C" {
unsigned long millis_stub_ms = 0;
}
