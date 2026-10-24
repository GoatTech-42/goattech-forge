#pragma once
struct PlannerStub { bool queued = false; bool has_blocks_queued() { return queued; } };
extern PlannerStub planner;
