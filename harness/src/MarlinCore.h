#pragma once
struct MarlinStub { bool active = false, paused = false;
  bool printingIsActive() { return active; } bool printingIsPaused() { return paused; } };
extern MarlinStub marlin;
