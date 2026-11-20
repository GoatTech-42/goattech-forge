// F1(a) host harness: drives Marlin's REAL Planner and Temperature modules
// (compiled from the patched tree by harness/build-real.sh) and prints a
// deterministic report for tests/test-harness-real-planner.sh to check.
//
// Usage: harness-real [--steps-x N] [--gcode FILE [--blocks]] [--emode-table]
//   --steps-x N  override X steps/mm after loading the config defaults
//                (used by the test's negative check).
//   --gcode FILE replay a G-code file through the real Planner instead of the
//                built-in moves (F1b). Only linear moves and a short list of
//                no-motion commands are accepted; anything else fails closed.
//   --blocks     with --gcode, print one line per block the planner produced.
//   --emode-table print whether E is relative after each of the eight
//                two-command orderings of {G90,G91} and {M82,M83}, using
//                Marlin's own GcodeSuite methods (reference for the tests).
//
// Host simulation only. Nothing here touches or validates real hardware.

#include "MarlinCore.h"
#include "module/planner.h"
#include "module/temperature.h"
#include "harness_hooks.h"
#include "gcode/gcode.h"

// The host config in harness/config must be the one compiled, never the tree's.
#if !defined(FORGE_HOST_HARNESS_CONFIG) || !defined(FORGE_HOST_HARNESS_CONFIG_ADV)
  #error "harness-real must be built against harness/config/Configuration*.h"
#endif

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cctype>
#include <cmath>
#include <string>

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


// ---- F1(b): G-code replay through the real Planner ----------------------
// Moves are streamed: a block is popped (as the stepper would) only when the
// planner queue is full, so lookahead sees a realistic queue. There is no
// stepper ISR and time does not advance, so this replays geometry, step
// counts, speed limits and junction rates, not wall-clock timing.

struct Replay {
  long blocks = 0, rejected = 0, moves = 0, ignored = 0, rate_violations = 0;
  unsigned long steps[4] = {0, 0, 0, 0};
  double path_mm = 0;
  bool print_blocks = false;
};

static void pop_block(Replay &r) {
  for (int guard = 0; guard < 100000; ++guard) {
    block_t * const b = planner.get_current_block();
    if (!b) continue;
    if (b->initial_rate > b->nominal_rate || b->final_rate > b->nominal_rate) ++r.rate_violations;
    r.steps[0] += b->steps.a; r.steps[1] += b->steps.b; r.steps[2] += b->steps.c; r.steps[3] += b->steps.e;
    r.path_mm += b->millimeters;
    if (r.print_blocks)
      printf("rblock %ld steps=%lu,%lu,%lu,%lu mm=%.3f nominal_speed=%.2f\n", r.blocks,
        (unsigned long)b->steps.a, (unsigned long)b->steps.b, (unsigned long)b->steps.c, (unsigned long)b->steps.e,
        b->millimeters, b->nominal_speed);
    ++r.blocks;
    planner.release_current_block();
    return;
  }
  printf("error: planner never delivered a block\n"); exit(2);
}

// Decimal number as Marlin's parser reads it: optional sign, digits, optional
// fraction. No exponent, so "X10E2" is X10 followed by an E word, not 1000.
static float parse_decimal(const char *p, const char **end) {
  const char *q = p;
  if (*q == '+' || *q == '-') ++q;
  const char *digits = q;
  while (isdigit((unsigned char)*q)) ++q;
  if (*q == '.') { ++q; while (isdigit((unsigned char)*q)) ++q; }
  if (q == digits || (q == digits + 1 && *digits == '.')) { *end = p; return 0; }   // no number
  const std::string num(p, q - p);
  *end = q;
  return strtof(num.c_str(), nullptr);
}

// First word of the line ("G1", "M117") into cmd/num; returns the rest.
static bool parse_command(const std::string &line, char *cmd, int *num, size_t *rest) {
  size_t i = 0;
  while (i < line.size() && isspace((unsigned char)line[i])) ++i;
  if (i >= line.size()) { *cmd = 0; return true; }
  *cmd = (char)toupper((unsigned char)line[i++]);
  // The command number is a whole integer: a missing number or a fraction
  // ("G1.5", "G X10") is not a command we know, so it must not become G1 or G0.
  const size_t start = i;
  long n = 0;
  while (i < line.size() && isdigit((unsigned char)line[i])) { n = n * 10 + (line[i] - '0'); if (n > 9999) return false; ++i; }
  if (i == start || (i < line.size() && line[i] == '.')) return false;
  *num = (int)n;
  *rest = i;
  return true;
}

// has[] marks every word letter seen; hasval[] only those followed by a number.
// A repeated letter overwrites both, so the last occurrence decides, as in
// Marlin's FASTER_GCODE_PARSER (parser.cpp: set() rewrites param[] per word).
static void parse_words(const std::string &line, size_t i, float val[26], bool has[26], bool hasval[26]) {
  for (int k = 0; k < 26; ++k) has[k] = hasval[k] = false;
  while (i < line.size()) {
    if (isspace((unsigned char)line[i])) { ++i; continue; }
    const char w = (char)toupper((unsigned char)line[i++]);
    if (!isalpha((unsigned char)w)) { printf("error: bad token near '%c'\n", w); exit(3); }
    while (i < line.size() && isspace((unsigned char)line[i])) ++i;
    const char *end = nullptr;
    val[w - 'A'] = parse_decimal(line.c_str() + i, &end);
    has[w - 'A'] = true;
    hasval[w - 'A'] = end != line.c_str() + i;
    i = end - line.c_str();
  }
}

static int replay_gcode(const char *path, bool print_blocks) {
  FILE *f = fopen(path, "rb");
  if (!f) { fprintf(stderr, "cannot open %s\n", path); return 66; }
  Replay r; r.print_blocks = print_blocks;
  thermalManager.allow_cold_extrude = true;   // no heater simulation: hotend treated as hot
  harness_millis = 1000;
  xyze_pos_t pos{0}; planner.set_position_mm(pos);
  // Marlin's relative-mode state (gcode.h): G90/G91 replace the whole state,
  // including any M82/M83 choice, so G91 makes E relative and G90 makes it
  // absolute again; M82/M83 then override E until the next G90/G91.
  bool rel_xyz = false, rel_e = false; int e_mode = 0;   // e_mode: 0 follow G90/G91, 1 M82, 2 M83
  float feed = 25;                            // mm/s until the file sets F
  long lineno = 0, unsupported = 0;
  for (;;) {
    // Whole physical line, any length, so a comment can never be cut in two.
    std::string line; int ch;
    while ((ch = getc(f)) != EOF && ch != '\n') line.push_back((char)ch);
    if (ch == EOF && line.empty()) break;
    ++lineno;
    const size_t semi = line.find(';');
    if (semi != std::string::npos) line.erase(semi);
    char cmd; int num; size_t rest; float v[26]; bool has[26], hasval[26];
    if (!parse_command(line, &cmd, &num, &rest)) {
      printf("unsupported line %ld: malformed command\n", lineno);
      ++unsupported;
      continue;
    }
    if (cmd == 0) continue;   // blank line
    // M117 carries free text, not words: ignore it before any word parsing.
    if (cmd == 'M' && num == 117) { ++r.ignored; continue; }
    parse_words(line, rest, v, has, hasval);
    // Compare letter and number separately: a packed key such as
    // letter*1000 + number would make F1092 equal to G92.
    auto is = [&](const char c, const int n) { return cmd == c && num == n; };
    // An X/Y/Z/E word whose last occurrence has no number ("G1 X", "G1 X10 X").
    // Pinned Marlin keeps the last occurrence of a letter (FASTER_GCODE_PARSER,
    // parser.cpp set()) and get_destination_from_command() reads each axis with
    // parser.seenval(), which is false then, so that axis keeps its position.
    // That is a defined firmware reading, not a bug, but it is outside the
    // modelled subset: refuse the line before the feed rate or any position changes.
    char novalue = 0;
    if (cmd == 'G' && (num == 0 || num == 1))
      for (const char a : { 'X', 'Y', 'Z', 'E' }) if (has[a - 'A'] && !hasval[a - 'A']) { novalue = a; break; }
    if (novalue) {
      printf("unsupported line %ld: G%d %c without a value (not modelled; Marlin's seenval() leaves that axis where it is)\n",
        lineno, num, novalue);
      ++unsupported;
    }
    else if (cmd == 'G' && (num == 0 || num == 1)) {
      if (has['F' - 'A']) feed = v['F' - 'A'] / 60.0f;
      const bool e_relative = e_mode == 2 ? true : e_mode == 1 ? false : rel_e;
      xyze_pos_t t = pos;
      if (has['X' - 'A']) t.x = rel_xyz ? pos.x + v['X' - 'A'] : v['X' - 'A'];
      if (has['Y' - 'A']) t.y = rel_xyz ? pos.y + v['Y' - 'A'] : v['Y' - 'A'];
      if (has['Z' - 'A']) t.z = rel_xyz ? pos.z + v['Z' - 'A'] : v['Z' - 'A'];
      if (has['E' - 'A']) t.e = e_relative ? pos.e + v['E' - 'A'] : v['E' - 'A'];
      ++r.moves;
      while (planner.is_full()) pop_block(r);
      if (!planner.buffer_line(t, feed, 0)) ++r.rejected;
      pos = t;
    }
    else if (is('G', 90)) { rel_xyz = rel_e = false; e_mode = 0; }
    else if (is('G', 91)) { rel_xyz = rel_e = true; e_mode = 0; }
    else if (is('M', 82)) e_mode = 1;
    else if (is('M', 83)) e_mode = 2;
    else if (is('G', 21)) { /* millimetres: already the unit */ }
    else if (is('G', 28)) {
      // Simplified homing: a position reset to 0,0,0 without motion. Let
      // queued blocks finish first, then resync every axis like Marlin's
      // sync_plan_position() after homing.
      while (planner.has_blocks_queued()) pop_block(r);
      pos.x = pos.y = pos.z = 0;
      planner.set_position_mm(pos);
    }
    else if (is('G', 92)) {
      // Only G92 with no words (a no-op) or with E and a value is modelled.
      // Workspace offsets are on in this config, so a real G92 X/Y/Z shifts
      // the workspace instead of the planner position; that is not modelled,
      // so any other word is refused here, before anything changes.
      bool other = false;
      for (int k = 0; k < 26; ++k) if (has[k] && k != 'E' - 'A') other = true;
      if (other || (has['E' - 'A'] && !hasval['E' - 'A'])) {
        printf("unsupported line %ld: G92 with %s (only G92 E<value> or bare G92 is modelled)\n", lineno,
          other ? "a word other than E" : "E and no value");
        ++unsupported;
      }
      else if (has['E' - 'A']) {
        // G92.cpp: E is set directly and synced with sync_plan_position_e(),
        // i.e. planner.set_e_position_mm(), only when it changes by more than
        // NEAR_ZERO; X/Y/Z planner positions are never touched. Queued blocks
        // are drained first (as before), so the setter takes its no-blocks
        // branch; the sync block the firmware would queue instead is not modelled.
        while (planner.has_blocks_queued()) pop_block(r);
        const float e = v['E' - 'A'];
        if (!NEAR_ZERO(e - pos.e)) { pos.e = e; planner.set_e_position_mm(pos.e); }
      }
      // bare G92: no word seen, nothing changes (as in G92.cpp)
    }
    else if (is('M', 400)) { while (planner.has_blocks_queued()) pop_block(r); }   // finish moves
    else if (cmd == 'G' && num == 4) ++r.ignored;
    else if (cmd == 'M' && (num == 104 || num == 109 || num == 140 || num == 190 || num == 106 || num == 107 ||
                            num == 84 || num == 73 || num == 105)) ++r.ignored;
    else {
      // Anything else could change motion (arcs, G20, M203/M204/M205, M220/M221 ...).
      printf("unsupported line %ld: %c%d\n", lineno, cmd, num);
      ++unsupported;
    }
  }
  if (ferror(f)) { fprintf(stderr, "read error on %s\n", path); fclose(f); return 74; }
  fclose(f);
  while (planner.has_blocks_queued()) pop_block(r);
  const char *base = strrchr(path, '/'); base = base ? base + 1 : path;
  printf("replay file=%s lines=%ld moves=%ld rejected=%ld blocks=%ld ignored=%ld unsupported=%ld\n",
    base, lineno, r.moves, r.rejected, r.blocks, r.ignored, unsupported);
  printf("replay steps=%lu,%lu,%lu,%lu\n", r.steps[0], r.steps[1], r.steps[2], r.steps[3]);
  printf("replay path_mm=%.3f\n", r.path_mm);
  printf("replay rate_violations=%ld\n", r.rate_violations);
  // rate_violations is reported, not an exit failure: the planner's own
  // minimum-segment-time slowdown can leave a short block with a junction rate
  // above its slowed nominal rate, and the tests assert the count where it matters.
  return unsupported ? 3 : 0;
}

// ---- E-mode reference: Marlin's own GcodeSuite relative-mode rules ------
// gcode.cpp is not linked, so define the one static the inline methods use.
relative_t GcodeSuite::axis_relative;

// G90()/G91() are set_relative_mode(false/true) (gcode.h) and M82()/M83() are
// set_e_absolute()/set_e_relative() (units/M82_M83.cpp); this applies exactly
// those inline methods, starting from the constructor's AXIS_RELATIVE_MODES
// state, and prints GcodeSuite::axis_is_relative(E_AXIS) for each ordering.
static void emode_apply(const char *c) {
  if (!strcmp(c, "G90")) GcodeSuite::set_relative_mode(false);
  else if (!strcmp(c, "G91")) GcodeSuite::set_relative_mode(true);
  else if (!strcmp(c, "M82")) GcodeSuite::set_e_absolute();
  else GcodeSuite::set_e_relative();
}

static int emode_table() {
  const char * const g[] = { "G90", "G91" }, * const m[] = { "M82", "M83" };
  for (const char *a : g) for (const char *b : m) for (int order = 0; order < 2; ++order) {
    GcodeSuite fresh;   // constructor resets axis_relative to AXIS_RELATIVE_MODES
    (void)fresh;
    const char *first = order ? b : a, *second = order ? a : b;
    emode_apply(first); emode_apply(second);
    printf("emode %s,%s e_relative=%d\n", first, second, (int)GcodeSuite::axis_is_relative(E_AXIS));
  }
  return 0;
}

int main(int argc, char **argv) {
  float steps_x = 0;
  const char *gcode = nullptr; bool print_blocks = false;
  for (int i = 1; i < argc; ++i) {
    if (!strcmp(argv[i], "--steps-x") && i + 1 < argc) steps_x = atof(argv[++i]);
    else if (!strcmp(argv[i], "--gcode") && i + 1 < argc) gcode = argv[++i];
    else if (!strcmp(argv[i], "--blocks")) print_blocks = true;
    else if (!strcmp(argv[i], "--emode-table")) return emode_table();
    else { fprintf(stderr, "usage: %s [--steps-x N] [--gcode FILE [--blocks]] [--emode-table]\n", argv[0]); return 64; }
  }

  planner.init();
  load_config_defaults(steps_x);
  thermalManager.extrude_min_temp = EXTRUDE_MINTEMP;
  printf("config steps_per_mm=%.2f,%.2f,%.2f,%.2f\n",
    planner.settings.axis_steps_per_mm[X_AXIS], planner.settings.axis_steps_per_mm[Y_AXIS],
    planner.settings.axis_steps_per_mm[Z_AXIS], planner.settings.axis_steps_per_mm[E_AXIS]);

  if (gcode) return replay_gcode(gcode, print_blocks);

  xyze_pos_t origin{0}; planner.set_position_mm(origin);

  // Travel moves: X, Y, diagonal back, Z lift
  harness_millis = 1000;
  // One statement per move: each call changes the planner position, and the
  // operands of + have no guaranteed evaluation order.
  int queued = 0;
  queued += move(10, 0, 0, 0, 50);
  queued += move(10, 10, 0, 0, 50);
  queued += move(0, 0, 0, 0, 100);
  queued += move(0, 0, 0.2f, 0, 5);
  printf("queued %d\n", queued);
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
