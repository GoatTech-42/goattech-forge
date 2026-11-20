#pragma once
#define BED_MAXTEMP 125
#define BED_OVERSHOOT 10
#define BED_MAX_TARGET (BED_MAXTEMP - BED_OVERSHOOT)
struct TempStub {
  int hotend_max_target(int) { return 260; }
  float degHotend(int) { return 23.5f; }
  float degBed() { return 24.0f; }
};
extern TempStub thermalManager;
