#pragma once
struct PlannerStub { bool queued=false, leveling_active=true; float extruder_advance_K[1]={0.04f};
  struct { float acceleration=3000; } settings; bool has_blocks_queued(){return queued;} };
extern PlannerStub planner;
struct RecoveryStub { bool enabled=false; };
extern RecoveryStub recovery;
