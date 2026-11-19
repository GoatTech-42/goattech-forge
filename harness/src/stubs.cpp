// Host stubs for symbols the real planner.cpp and temperature.cpp reference
// but the harness does not exercise (UI, serial, HAL). Defined by mangled name
// so no Marlin headers are needed; data is zeroed storage, functions return 0.
#include <cstdint>

extern "C" alignas(16) unsigned char stub_d6[512] __asm__("HMI_flag") = {0};
extern "C" alignas(16) unsigned char stub_d7[512] __asm__("M112_KILL_STR") = {0};
extern "C" alignas(16) unsigned char stub_d8[512] __asm__("NUL_STR") = {0};
extern "C" alignas(16) unsigned char stub_d9[512] __asm__("_ZN10CardReader4flagE") = {0};
extern "C" alignas(16) unsigned char stub_d10[512] __asm__("_ZN10GcodeSuite16previous_move_msE") = {0};
extern "C" alignas(16) unsigned char stub_d11[512] __asm__("_ZN11GCodeParser18volumetric_enabledE") = {0};
extern "C" alignas(16) unsigned char stub_d15[512] __asm__("_ZN4Gpio6loggerE") = {0};
extern "C" alignas(16) unsigned char stub_d16[512] __asm__("_ZN4Gpio7pin_mapE") = {0};
extern "C" alignas(16) unsigned char stub_d17[512] __asm__("_ZN5Clock15time_multiplierE") = {0};
extern "C" alignas(16) unsigned char stub_d18[512] __asm__("_ZN5Clock7startupE") = {0};
extern "C" alignas(16) unsigned char stub_d19[512] __asm__("_ZN6Marlin15wait_for_heatupE") = {0};
extern "C" alignas(16) unsigned char stub_d20[512] __asm__("_ZN6Marlin5stateE") = {0};
extern "C" alignas(16) unsigned char stub_d21[512] __asm__("_ZN6Motion8positionE") = {0};
extern "C" alignas(16) unsigned char stub_d22[512] __asm__("_ZN7Stepper19abort_current_blockE") = {0};
extern "C" alignas(16) unsigned char stub_d23[512] __asm__("_ZN8MarlinUI21status_reset_callbackE") = {0};
extern "C" alignas(16) unsigned char stub_d24[512] __asm__("_ZN9MarlinHAL9active_chE") = {0};
extern "C" alignas(16) unsigned char stub_d26[512] __asm__("dwin_heat_time") = {0};
extern "C" alignas(16) unsigned char stub_d27[512] __asm__("end_flag") = {0};
extern "C" alignas(16) unsigned char stub_d28[512] __asm__("fans") = {0};
extern "C" alignas(16) unsigned char stub_d29[512] __asm__("lroundf") = {0};
extern "C" alignas(16) unsigned char stub_d30[512] __asm__("marlin_debug_flags") = {0};
extern "C" alignas(16) unsigned char stub_d31[512] __asm__("memset") = {0};
extern "C" alignas(16) unsigned char stub_d32[512] __asm__("sprintf") = {0};
extern "C" alignas(16) unsigned char stub_d33[512] __asm__("sqrtf") = {0};
extern "C" alignas(16) unsigned char stub_d34[512] __asm__("strlen") = {0};
extern "C" alignas(16) unsigned char stub_d35[512] __asm__("usb_serial") = {0};
extern "C" long stub_f36() __asm__("_Z10SERIAL_EOLv");
long stub_f36() { return 0; }
extern "C" long stub_f37() __asm__("_Z11DWIN_Updatev");
long stub_f37() { return 0; }
extern "C" long stub_f38() __asm__("_Z11SERIAL_ECHO10SerialChar");
long stub_f38() { return 0; }
extern "C" long stub_f39() __asm__("_Z11SERIAL_ECHOIPK19__FlashStringHelperEvT_");
long stub_f39() { return 0; }
extern "C" long stub_f40() __asm__("_Z11SERIAL_ECHOIfEvT_");
long stub_f40() { return 0; }
extern "C" long stub_f41() __asm__("_Z11analogWritesi");
long stub_f41() { return 0; }
extern "C" long stub_f42() __asm__("_Z15HAL_timer_starthj");
long stub_f42() { return 0; }
extern "C" long stub_f43() __asm__("_Z17SERIAL_ECHO_STARTv");
long stub_f43() { return 0; }
extern "C" long stub_f44() __asm__("_Z18SERIAL_ERROR_STARTv");
long stub_f44() { return 0; }
extern "C" long stub_f45() __asm__("_Z22DWIN_Popup_Temperatureba");
long stub_f45() { return 0; }
extern "C" long stub_f46() __asm__("_Z26HAL_timer_enable_interrupth");
long stub_f46() { return 0; }
extern "C" long stub_f47() __asm__("_Z27HAL_timer_disable_interrupth");
long stub_f47() { return 0; }
extern "C" long stub_f48() __asm__("_Z27HAL_timer_interrupt_enabledh");
long stub_f48() { return 0; }
extern "C" long stub_f49() __asm__("_Z3mapttttt");
long stub_f49() { return 0; }
extern "C" long stub_f50() __asm__("_Z6millisv");
long stub_f50() { return 0; }
extern "C" long stub_f51() __asm__("_Z7dtostrfdahPc");
long stub_f51() { return 0; }
extern "C" long stub_f52() __asm__("_ZN10GcodeSuite23process_subcommands_nowEPK19__FlashStringHelper");
long stub_f52() { return 0; }
extern "C" long stub_f53() __asm__("_ZN12PrintCounter5_stopEb");
long stub_f53() { return 0; }
extern "C" long stub_f54() __asm__("_ZN15EmergencyParser14killed_by_M112E");
long stub_f54() { return 0; }
extern "C" long stub_f55() __asm__("_ZN15EmergencyParser16sd_abort_by_M524E");
long stub_f55() { return 0; }
extern "C" long stub_f56() __asm__("_ZN15EmergencyParser17quickstop_by_M410E");
long stub_f56() { return 0; }
extern "C" long stub_f57() __asm__("_ZN3Fan9init_pinsEv");
long stub_f57() { return 0; }
extern "C" long stub_f58() __asm__("_ZN6HostUI8notify_PEPKc");
long stub_f58() { return 0; }
extern "C" long stub_f59() __asm__("_ZN6Marlin16startOrResumeJobEv");
long stub_f59() { return 0; }
extern "C" long stub_f60() __asm__("_ZN6Marlin4idleEb");
long stub_f60() { return 0; }
extern "C" long stub_f61() __asm__("_ZN6Marlin4killEPK19__FlashStringHelperS2_b");
long stub_f61() { return 0; }
extern "C" long stub_f62() __asm__("_ZN6Motion17get_move_distanceERK7XYZEvalIfE");
long stub_f62() { return 0; }
extern "C" long stub_f63() __asm__("_ZN6Motion17quickstop_stepperEv");
long stub_f63() { return 0; }
extern "C" long stub_f64() __asm__("_ZN6Motion19homing_needed_errorEh");
long stub_f64() { return 0; }
extern "C" long stub_f65() __asm__("_ZN6Nozzle4parkEhRK6XYZvalIfE");
long stub_f65() { return 0; }
extern "C" long stub_f66() __asm__("_ZN7Stepper11enable_axisE8AxisEnum");
long stub_f66() { return 0; }
extern "C" long stub_f67() __asm__("_ZN7Stepper12set_positionERK7XYZEvalIiE");
long stub_f67() { return 0; }
extern "C" long stub_f68() __asm__("_ZN7Stepper13is_block_busyEPK12PlannerBlock");
long stub_f68() { return 0; }
extern "C" long stub_f69() __asm__("_ZN7Stepper14set_e_positionERKi");
long stub_f69() { return 0; }
extern "C" long stub_f70() __asm__("_ZN7Stepper15enable_extruderEv");
long stub_f70() { return 0; }
extern "C" long stub_f71() __asm__("_ZN7Stepper17endstop_triggeredE8AxisEnum");
long stub_f71() { return 0; }
extern "C" long stub_f72() __asm__("_ZN7Stepper18triggered_positionE8AxisEnum");
long stub_f72() { return 0; }
extern "C" long stub_f73() __asm__("_ZN7Stepper20disable_all_steppersEv");
long stub_f73() { return 0; }
extern "C" long stub_f74() __asm__("_ZN7Stepper8positionE8AxisEnum");
long stub_f74() { return 0; }
extern "C" long stub_f75() __asm__("_ZN8Endstops4pollEv");
long stub_f75() { return 0; }
extern "C" long stub_f76() __asm__("_ZN8MarlinUI11_set_statusEPKcbb");
long stub_f76() { return 0; }
extern "C" long stub_f77() __asm__("_ZN8MarlinUI12reset_statusEb");
long stub_f77() { return 0; }
extern "C" long stub_f78() __asm__("_ZN8MarlinUI15status_printf_PEaPKcz");
long stub_f78() { return 0; }
extern "C" long stub_f79() __asm__("_ZN9MarlinHAL8_strlcpyEPcPKcm");
long stub_f79() { return 0; }
extern "C" long stub_f80() __asm__("_ZN9MarlinHAL9adc_valueEv");
long stub_f80() { return 0; }
extern "C" long stub_f81() __asm__("_ZN9Stopwatch8durationEv");
long stub_f81() { return 0; }
extern "C" void stub_delay(unsigned long) __asm__("delay");
void stub_delay(unsigned long) {}
extern "C" alignas(16) unsigned char stub_dm[512] __asm__("fans") = {0};
