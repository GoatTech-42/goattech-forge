// F1(a) host harness: drives Marlin's REAL Planner and Temperature modules
// (compiled from the patched tree by harness/build-real.sh) and prints a
// deterministic report for tests/test-harness-real-planner.sh to check.
//
// Usage: harness-real [--steps-x N]
//   --steps-x N  override X steps/mm after loading the config defaults
//                (used by the test's negative check).
//
// Host simulation only. Nothing here touches or validates real hardware.

#include "MarlinCore.h"
#include "module/planner.h"
#include "module/temperature.h"
#include "harness_hooks.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

static const float steps_default[] = DEFAULT_AXIS_STEPS_PER_UNIT;
static const float feed_default[] = DEFAULT_MAX_FEEDRATE;
static const float accel_default[] = DEFAULT_MAX_ACCELERATION;

static void load_config_defaults(const float steps_x) {
  for (uint8_t i = 0; i < DISTINCT_AXES; ++i) {
    planner.settings.axis_steps_per_mm[i] = steps_default[i];
    planner.settings.max_feedrate_mm_s[i] = feed_default[i];
    planner.settings.max_acceleration_mm_per_s2[i] = accel_default[i];
  }
  if (steps_x > 0) planner.settings.axis_steps_per_mm[X_AXIS] = steps_x;
  planner.settings.min_segment_time_us = DEFAULT_MINSEGMENTTIME;
  planner.settings.acceleration = DEFAULT_ACCELERATION;
  planner.settings.retract_acceleration = DEFAULT_RETRACT_ACCELERATION;
  planner.settings.travel_acceleration = DEFAULT_TRAVEL_ACCELERATION;
  planner.settings.min_feedrate_mm_s = DEFAULT_MINIMUMFEEDRATE;
  planner.settings.min_travel_feedrate_mm_s = DEFAULT_MINTRAVELFEEDRATE;
  #if HAS_JUNCTION_DEVIATION
    planner.junction_deviation_mm = float(JUNCTION_DEVIATION_MM);
  #endif
  planner.refresh_positioning();
  planner.refresh_acceleration_rates();
}

static int blocks_seen = 0;

// Pop every block the planner will hand to the stepper and print it.
static void drain(const char *label) {
  printf("batch %s queued=%u\n", label, planner.movesplanned());
  for (int guard = 0; guard < 1000 && planner.has_blocks_queued(); ++guard) {
    block_t * const b = planner.get_current_block();
    if (!b) continue;   // delivery delay or trapezoid not ready yet
    printf("block %d steps=%lu,%lu,%lu,%lu events=%lu mm=%.3f nominal_speed=%.2f nominal_rate=%lu\n",
      blocks_seen++,
      (unsigned long)b->steps.a, (unsigned long)b->steps.b, (unsigned long)b->steps.c, (unsigned long)b->steps.e,
      (unsigned long)b->step_event_count, b->millimeters, b->nominal_speed, (unsigned long)b->nominal_rate);
    planner.release_current_block();
  }
  if (planner.has_blocks_queued()) { printf("error: blocks left undrained\n"); exit(2); }
}

static bool move(const float x, const float y, const float z, const float e, const float fr) {
  xyze_pos_t p; p.set(x, y, z, e);
  return planner.buffer_line(p, fr, 0);
}

int main(int argc, char **argv) {
  float steps_x = 0;
  for (int i = 1; i < argc; ++i) {
    if (!strcmp(argv[i], "--steps-x") && i + 1 < argc) steps_x = atof(argv[++i]);
    else { fprintf(stderr, "usage: %s [--steps-x N]\n", argv[0]); return 64; }
  }

  planner.init();
  load_config_defaults(steps_x);
  thermalManager.extrude_min_temp = EXTRUDE_MINTEMP;
  printf("config steps_per_mm=%.2f,%.2f,%.2f,%.2f\n",
    planner.settings.axis_steps_per_mm[X_AXIS], planner.settings.axis_steps_per_mm[Y_AXIS],
    planner.settings.axis_steps_per_mm[Z_AXIS], planner.settings.axis_steps_per_mm[E_AXIS]);

  xyze_pos_t origin{0}; planner.set_position_mm(origin);

  // Travel moves: X, Y, diagonal back, Z lift
  harness_millis = 1000;
  printf("queued %d\n", move(10, 0, 0, 0, 50) + move(10, 10, 0, 0, 50) + move(0, 0, 0, 0, 100) + move(0, 0, 0.2f, 0, 5));
  drain("travel");

  // Printing move with a cold hotend: PREVENT_COLD_EXTRUSION must drop E
  printf("hotend_cold=%d\n", thermalManager.tooColdToExtrude(0));
  printf("queued %d\n", move(20, 0, 0.2f, 1, 30));
  drain("cold_extrude");

  // Same move once cold extrusion is allowed: E steps come back
  thermalManager.allow_cold_extrude = true;
  printf("queued %d\n", move(30, 0, 0.2f, 2, 30));
  drain("extrude");

  // Temperature: target setters, max-target clamp, thermistor conversion
  thermalManager.setTargetHotend(210, 0);
  printf("hotend target=%d\n", thermalManager.degTargetHotend(0));
  thermalManager.setTargetHotend(400, 0);
  printf("hotend clamp=%d max_target=%d\n", thermalManager.degTargetHotend(0), thermalManager.hotend_max_target(0));
  thermalManager.setTargetBed(60);
  printf("bed target=%d\n", thermalManager.degTargetBed());
  const raw_adc_t raws[] = { 1000, 4000, 8000, 12000, 15000 };
  for (const raw_adc_t r : raws)
    printf("thermistor raw=%u hotend_c=%.1f bed_c=%.1f\n", (unsigned)r,
      thermalManager.analog_to_celsius_hotend(r, 0), thermalManager.analog_to_celsius_bed(r));

  printf("blocks total=%d\n", blocks_seen);
  return 0;
}
