// Real pinned parser, M200 handler and planner, with hardware boundaries stubbed.
#include "MarlinCore.h"
#include "module/planner.h"
#include "module/temperature.h"
#include "harness_hooks.h"
#include "gcode/gcode.h"
#include "gcode/parser.cpp"
#include "m200-handler.inc"
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
int8_t GcodeSuite::get_target_extruder_from_command() { return 0; }
void GcodeSuite::M200_report(const bool) {}
// Dispatch boundary limited to the one real handler under test.
void GcodeSuite::process_parsed_command(bool) { M200(); }
static void command(const char *s) {
  char buf[96]; snprintf(buf, sizeof(buf), "%s", s);
  parser.parse(buf); GcodeSuite::process_parsed_command();
}
int main(int argc, char **argv) {
  if (argc != 2) return 2;
  planner.init();
  const float steps[] = DEFAULT_AXIS_STEPS_PER_UNIT;
  const float feed[] = DEFAULT_MAX_FEEDRATE;
  const float accel[] = DEFAULT_MAX_ACCELERATION;
  for (uint8_t i = 0; i < DISTINCT_AXES; ++i) {
    planner.settings.axis_steps_per_mm[i] = steps[i];
    planner.settings.max_feedrate_mm_s[i] = feed[i];
    planner.settings.max_acceleration_mm_per_s2[i] = accel[i];
  }
  planner.settings.acceleration = DEFAULT_ACCELERATION;
  planner.settings.retract_acceleration = DEFAULT_RETRACT_ACCELERATION;
  planner.settings.travel_acceleration = DEFAULT_TRAVEL_ACCELERATION;
  planner.settings.min_segment_time_us = DEFAULT_MINSEGMENTTIME;
  planner.refresh_positioning(); planner.refresh_acceleration_rates();
  thermalManager.allow_cold_extrude = true;
  command("M200 D1.75 S1");
  printf("dirty enabled=%d factor=%.6f\n", parser.volumetric_enabled, planner.e_factor[0]);
  if (!parser.volumetric_enabled || planner.e_factor[0] > 0.42f) return 2;
  std::ifstream file(argv[1]);
  if (!file) return 2;
  bool saw_reset = false, saw_extrusion = false;
  std::string line;
  while (std::getline(file, line)) {
    if (line.rfind("M200", 0) == 0) {
      if (saw_extrusion) { puts("FAIL volumetric: reset after first extrusion"); return 1; }
      command(line.c_str()); saw_reset = true;
    }
    if (line.rfind("G1 ", 0) == 0 && line.find(" E") != std::string::npos) {
      saw_extrusion = true; break;
    }
  }
  xyze_pos_t origin{0}; planner.set_position_mm(origin);
  xyze_pos_t target{0}; target.e = 1;
  harness_millis = 1000;
  planner.buffer_line(target, 5, 0);
  unsigned long e_steps = 0;
  for (int i = 0; i < 1000 && planner.has_blocks_queued(); ++i) {
    block_t *b = planner.get_current_block();
    if (b) { e_steps += b->steps.e; planner.release_current_block(); }
  }
  printf("probe reset=%d extrusion=%d enabled=%d factor=%.6f e_steps=%lu\n",
         saw_reset, saw_extrusion, parser.volumetric_enabled, planner.e_factor[0], e_steps);
  const bool ok = saw_reset && saw_extrusion && !parser.volumetric_enabled && e_steps == 715;
  puts(ok ? "PASS volumetric: first extrusion uses linear filament units" :
            "FAIL volumetric: first extrusion uses stale or unproved units");
  return ok ? 0 : 1;
}
