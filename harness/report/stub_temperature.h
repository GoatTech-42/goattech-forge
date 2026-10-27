#pragma once
struct TempStub { float hn=23.5f, hb=24.0f, tn=0, tb=0;
  int hotend_max_target(int){return 300;} float degHotend(int){return hn;} float degBed(){return hb;}
  float degTargetHotend(int){return tn;} float degTargetBed(){return tb;} };
extern TempStub thermalManager;
