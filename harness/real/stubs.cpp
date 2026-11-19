// Host stubs for the symbols Marlin's real planner.cpp and temperature.cpp
// reference but the F1 harness does not exercise (UI, serial, HAL timers,
// stepper ISR, gcode). Built against the same Marlin tree and host config as
// the real modules, so every stub has its real declared type.
//
// Stubs that change behaviour on purpose:
//  - millis() returns harness_millis, which main.cpp advances explicitly.
//  - MarlinHAL::adc_value() returns harness_adc, a stubbed ADC reading.
//  - Motion::get_move_distance() is the cartesian formula from motion.cpp.
//  - Stepper::is_block_busy() is always false (no stepper ISR on the host).
// Everything else is a no-op or zero. Host simulation only.

#include "MarlinCore.h"
#include "module/planner.h"
#include "module/stepper.h"
#include "module/motion.h"
#include "module/temperature.h"
#include "module/endstops.h"
#include "module/printcounter.h"
#include "module/fans.h"
#include "libs/nozzle.h"
#include "libs/stopwatch.h"
#include "gcode/gcode.h"
#include "gcode/parser.h"
#include "feature/e_parser.h"
#include "feature/host_actions.h"
#include "lcd/marlinui.h"
#include "lcd/dwin/creality/dwin.h"
#include "sd/cardreader.h"
#include "HAL/LINUX/hardware/Clock.h"
#include "HAL/LINUX/hardware/Gpio.h"

#include "harness_hooks.h"

// The host config in harness/config must be the one compiled, never the tree's.
#if !defined(FORGE_HOST_HARNESS_CONFIG) || !defined(FORGE_HOST_HARNESS_CONFIG_ADV)
  #error "harness-real must be built against harness/config/Configuration*.h"
#endif

uint32_t harness_millis = 0;
uint16_t harness_adc = 0;

// HAL / platform
unsigned long millis() { return harness_millis; }
extern "C" void delay(const int) {}
uint16_t MarlinHAL::adc_value() { return harness_adc; }
uint8_t MarlinHAL::active_ch = 0;
size_t MarlinHAL::_strlcpy(char *dst, const char *src, size_t dsize) {
  if (!dsize) return 0;
  size_t n = 0;
  while (n + 1 < dsize && src[n]) { dst[n] = src[n]; ++n; }
  dst[n] = '\0';
  return n;
}
void HAL_timer_start(const uint8_t, const uint32_t) {}
void HAL_timer_enable_interrupt(const uint8_t) {}
void HAL_timer_disable_interrupt(const uint8_t) {}
bool HAL_timer_interrupt_enabled(const uint8_t) { return false; }
void analogWrite(const pin_t, int) {}
int map(uint16_t x, uint16_t in_min, uint16_t in_max, uint16_t out_min, uint16_t out_max) {
  return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}
char *dtostrf(double v, signed char w, unsigned char p, char *s) { sprintf(s, "%*.*f", w, p, v); return s; }
MSerialT usb_serial(TERN0(EMERGENCY_PARSER, true));
std::chrono::nanoseconds Clock::startup = std::chrono::nanoseconds(0);
double Clock::time_multiplier = 1.0;
pin_data Gpio::pin_map[Gpio::pin_count + 1] = {};
IOLogger *Gpio::logger = nullptr;

// Serial output is discarded
uint8_t marlin_debug_flags = 0;
const char NUL_STR[] = "", M112_KILL_STR[] = "Killed. (M112)";
void SERIAL_EOL() {}
void SERIAL_ECHO_START() {}
void SERIAL_ERROR_START() {}
void SERIAL_ECHO(serial_char_t) {}
template <> void SERIAL_ECHO(FSTR_P) {}
template <> void SERIAL_ECHO(float) {}

// Marlin core
MarlinState Marlin::state = MarlinState::MF_RUNNING;
bool Marlin::wait_for_heatup = false;
void Marlin::idle(const bool) {}
void Marlin::kill(FSTR_P const, FSTR_P const, const bool) { fprintf(stderr, "kill() called\n"); exit(3); }
void Marlin::startOrResumeJob() {}

// Stepper (no ISR on host)
bool Stepper::abort_current_block = false;
bool Stepper::is_block_busy(const block_t * const) { return false; }
int32_t Stepper::position(const AxisEnum) { return 0; }
void Stepper::set_position(const xyze_long_t &) {}
void Stepper::set_e_position(const int32_t &) {}
void Stepper::enable_axis(const AxisEnum) {}
void Stepper::enable_extruder(E_TERN_(const uint8_t)) {}
void Stepper::disable_all_steppers() {}
void Stepper::endstop_triggered(const AxisEnum) {}
int32_t Stepper::triggered_position(const AxisEnum) { return 0; }
void Endstops::poll() {}

// Motion
xyze_pos_t Motion::position{0};
float Motion::get_move_distance(const xyze_pos_t &diff OPTARG(HAS_ROTATIONAL_AXES, bool &)) {
  if (!diff.x && !diff.y) return ABS(diff.z);
  return SQRT(sq(diff.x) + sq(diff.y) + sq(diff.z));
}
bool Motion::homing_needed_error(main_axes_bits_t) { return false; }
void Motion::quickstop_stepper() {}
void Nozzle::park(const uint8_t, const xyz_pos_t &) {}

// G-code, UI, SD, host
millis_t GcodeSuite::previous_move_ms = 0;
void GcodeSuite::process_subcommands_now(FSTR_P) {}
bool GCodeParser::volumetric_enabled = false;
bool EmergencyParser::killed_by_M112 = false;
bool EmergencyParser::quickstop_by_M410 = false;
bool EmergencyParser::sd_abort_by_M524 = false;
statusResetFunc_t MarlinUI::status_reset_callback = nullptr;
void MarlinUI::_set_status(const char * const, const bool, const bool) {}
void MarlinUI::reset_status(const bool) {}
void MarlinUI::status_printf_P(int8_t, PGM_P const, ...) {}
void HostUI::notify_P(PGM_P const) {}
card_flags_t CardReader::flag;
millis_t Stopwatch::duration() { return 0; }
bool PrintCounter::_stop(const bool) { return false; }
#define _FANDEF(N) Fan(N),
Fan fans[FAN_COUNT] = { REPEAT(FAN_COUNT, _FANDEF) };
#undef _FANDEF
void Fan::init_pins() {}
millis_t dwin_heat_time = 0;
HMI_Flag_t HMI_flag{};
bool end_flag = false;
void DWIN_Update() {}
void DWIN_Popup_Temperature(const bool, int8_t) {}
