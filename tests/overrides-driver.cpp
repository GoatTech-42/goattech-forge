// Real pinned parser, M220/M221 handlers and planner, with hardware boundaries stubbed.
#include "MarlinCore.h"
#include "module/planner.h"
#include "module/temperature.h"
#include "harness_hooks.h"
#include "gcode/gcode.h"
#include "gcode/parser.cpp"
#include "module/motion.h"
int16_t Motion::feedrate_percentage = 100;
void SERIAL_CHAR(char) {}
#include "m220-handler.inc"
#include "m221-handler.inc"
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
int8_t GcodeSuite::get_target_extruder_from_command() { return 0; }

// Dispatch boundary limited to the one real handler under test.
void GcodeSuite::process_parsed_command(bool) { if (parser.codenum == 220) M220(); else if (parser.codenum == 221) M221(); }
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
  parser.volumetric_enabled = false;
  planner.calculate_volumetric_multipliers();
  command("M220 S50"); command("M221 S150");
  printf("dirty speed=%d flow=%d factor=%.6f\n", motion.feedrate_percentage, planner.flow_percentage[0], planner.e_factor[0]);
  if (motion.feedrate_percentage != 50 || planner.flow_percentage[0] != 150) return 2;
  std::ifstream file(argv[1]);
  if (!file) return 2;
  bool saw_speed = false, saw_flow = false, saw_extrusion = false;
  std::string line;
  while (std::getline(file, line)) {
    if (line.rfind("M220",0)==0 || line.rfind("M221",0)==0) {
      command(line.c_str());
      saw_speed |= line.rfind("M220",0)==0;
      saw_flow |= line.rfind("M221",0)==0;
    }
    if (line.rfind("G1 ", 0) == 0 && line.find(" E") != std::string::npos) {
      saw_extrusion = true; break;
    }
  }
  xyze_pos_t origin{0}; planner.set_position_mm(origin);
  xyze_pos_t target{0}; target.x = 10; target.e = 1;
  harness_millis = 1000;
  planner.buffer_line(target, motion.mms_scaled(10), 0);
  unsigned long e_steps = 0; float speed = 0;
  for (int i = 0; i < 1000 && planner.has_blocks_queued(); ++i) {
    block_t *b = planner.get_current_block();
    if (b) { e_steps += b->steps.e; speed = b->nominal_speed; planner.release_current_block(); }
  }
  printf("probe resets=%d/%d extrusion=%d speedpct=%d flowpct=%d factor=%.6f e_steps=%lu speed=%.2f\n",
         saw_speed, saw_flow, saw_extrusion, motion.feedrate_percentage, planner.flow_percentage[0], planner.e_factor[0], e_steps, speed);
  const bool ok = saw_speed && saw_flow && saw_extrusion && motion.feedrate_percentage == 100
               && planner.flow_percentage[0] == 100 && e_steps == 715 && fabsf(speed - 10) < 0.01f;
  puts(ok ? "PASS overrides: representative move uses baseline speed and flow" :
            "FAIL overrides: first extrusion retains stale or unproved overrides");
  return ok ? 0 : 1;
}
