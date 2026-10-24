#pragma once
#define BED_MAXTEMP 100
struct TempStub {
  int hotend_max_target(int) { return 260; }
  float degHotend(int) { return 23.5f; }
  float degBed() { return 24.0f; }
};
extern TempStub thermalManager;
