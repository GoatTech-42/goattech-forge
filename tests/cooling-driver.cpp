// Actual pinned temperature command handlers, hardware wait boundaries stubbed.
#include <cstdio>
#include <cstring>
#include <string>
#include <fstream>
#include <cstdlib>
#define ENABLED(x) 0
#define DEBUGGING(x) 0
#define HAS_PREHEAT 0
#define TERN_(x,...) 
#define LCD_MESSAGE(x) ((void)0)
using celsius_t = int;
struct Parser {
  std::string line; const char *value = nullptr;
  bool seenval(char c) {
    auto p = line.find(c);
    if (p == std::string::npos || p+1 >= line.size()) return false;
    value = line.c_str()+p+1; return true;
  }
  int value_celsius() { return atoi(value); }
} parser;
struct Thermal {
  int hot = 0, bed = 0, hot_target = 0, bed_target = 0;
  int hot_waits = 0, bed_waits = 0;
  bool hot_skip = true, bed_skip = true;
  void setTargetHotend(int t, int) { hot_target = t; }
  void setTargetBed(int t) { bed_target = t; }
  bool isHeatingHotend(int) { return hot < hot_target; }
  bool isHeatingBed() { return bed < bed_target; }
  void set_heating_message(int, bool) {}
  void wait_for_hotend(int, bool skip) { ++hot_waits; hot_skip = skip; }
  void wait_for_bed(bool skip) { ++bed_waits; bed_skip = skip; }
  int degTargetBed() { return bed_target; }
  bool degBedNear(int) { return false; }
} thermalManager;
struct { template<class T> void set_status_reset_fn(T) {} } ui;
struct GcodeSuite {
  static int get_target_extruder_from_command() { return 0; }
  static void M104_M109(bool);
  static void M140_M190(bool);
};
#include "hotend-handler.inc"
#include "bed-handler.inc"
int main(int argc, char **argv) {
  if (argc != 4) return 2;
  const int bed_want = atoi(argv[2]), current = atoi(argv[3]);
  thermalManager.hot = thermalManager.bed = current;
  std::ifstream in(argv[1]); if (!in) return 2;
  std::string line;
  while (std::getline(in,line)) {
    parser.line = line;
    if (line.rfind("M104 ",0)==0) GcodeSuite::M104_M109(false);
    else if (line.rfind("M109 ",0)==0) GcodeSuite::M104_M109(true);
    else if (line.rfind("M140 ",0)==0) GcodeSuite::M140_M190(false);
    else if (line.rfind("M190 ",0)==0) GcodeSuite::M140_M190(true);
    else if (line.rfind("G1 ",0)==0 && line.find(" E")!=std::string::npos) break;
  }
  printf("request current=%d nozzle=%d bed=%d waits=%d/%d cooling_skip=%d/%d\n", current,
         thermalManager.hot_target, thermalManager.bed_target,
         thermalManager.hot_waits, thermalManager.bed_waits,
         thermalManager.hot_skip, thermalManager.bed_skip);
  bool ok = thermalManager.hot_target == 200 && thermalManager.bed_target == bed_want
         && thermalManager.hot_waits == 1 && thermalManager.bed_waits == 1
         && !thermalManager.hot_skip && thermalManager.bed_skip == (bed_want == 0);
  puts(ok ? "PASS cooling request: selected wait policy reaches real handlers" :
            "FAIL cooling request: selected wait policy not requested before extrusion");
  return ok ? 0 : 1;
}
