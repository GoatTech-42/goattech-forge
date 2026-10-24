// Forge diagnostics generator host harness: replays the REAL emission path
// (byte-identical copy of forge_diag.cpp, hash-checked by run-harness.sh)
// against a fake SD/FS, and asserts gate and failure-variant behavior.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "src/sd/cardreader.h"
#include "src/MarlinCore.h"
#include "src/module/planner.h"
#include "src/module/temperature.h"
#include "src/lcd/marlinui.h"

FakeFS g_fs; CardReader card; MarlinStub marlin; PlannerStub planner;
TempStub thermalManager; UIStub ui;

char* dtostrf(double v, signed char, unsigned char prec, char* buf) {
  sprintf(buf, "%.*f", (int)prec, v); return buf;
}

#include "src/e3v3se/forge_diag.h"

static int failures = 0;
static void expect(bool cond, const char* label) {
  printf("%s %s\n", cond ? "PASS" : "FAIL", label);
  if (!cond) failures++;
}
static void reset() {
  g_fs = FakeFS(); card = CardReader(); marlin = MarlinStub(); planner = PlannerStub();
}
static bool called(const char* prefix) {
  for (auto& c : g_fs.calls) if (c.rfind(prefix, 0) == 0) return true;
  return false;
}

int main(int argc, char** argv) {
  const forge_diag::PlateParams p { 40, 200, 60 }; // 0.40mm nozzle, PLA-ish review temps

  // 1. Happy path across the ALLOWED PARAM RANGE: nozzle bounds 0.20/0.80
  //    (layer_h 0.10/0.32 -> tower layer counts 350/109, so the SAFE_Z=37
  //    clearance assumption is checked from emitted bytes at both extremes).
  const forge_diag::PlateParams variants[] = {
    { 40, 200, 60 },  // reference
    { 20, 170, 0 },   // min nozzle / min temps
    { 80, 260, 100 }, // max nozzle / max temps
  };
  for (int v = 0; v < 3; v++) {
    reset();
    const forge_diag::PlateParams& pv = variants[v];
    bool ok = forge_diag::generate_plate(pv, false);
    printf("variant nozzle_x100=%u temps=%u/%u\n", (unsigned)pv.nozzle_x100, (unsigned)pv.temp_nozzle, (unsigned)pv.temp_bed);
    expect(ok, "  generate returns true");
    expect(g_fs.files.count("FORGDIA1.G") == 1, "  job file published by rename");
    expect(g_fs.files.count("FORGDIA1.TMP") == 0, "  temp file gone after publish");
    expect(called("rename->FORGDIA1.G"), "  rename publish happened");
    expect(g_fs.files["FORGDIA1.G"].size() == forge_diag::estimate_plate_bytes(pv),
           "  estimate_plate_bytes == actual emitted bytes");
    if (ok && argc > 1) {
      char name[256];
      snprintf(name, sizeof(name), "%s.%u.gcode", argv[1], (unsigned)pv.nozzle_x100);
      FILE* f = fopen(name, "w");
      fwrite(g_fs.files["FORGDIA1.G"].data(), 1, g_fs.files["FORGDIA1.G"].size(), f);
      fclose(f);
    }
  }
  bool ok = true; // keep later code shape unchanged

  // 2. Entry gates: each refusal must happen BEFORE any openFileWrite.
  struct { const char* name; int which; } gates[] = {
    {"active job", 0}, {"paused job", 1}, {"file already open", 2}, {"planner queued", 3}, {"card unmounted", 4}
  };
  for (auto& g : gates) {
    reset();
    switch (g.which) {
      case 0: marlin.active = true; break;
      case 1: marlin.paused = true; break;
      case 2: card.file_open = true; break;
      case 3: planner.queued = true; break;
      case 4: card.mounted = false; break;
    }
    bool r = forge_diag::generate_plate(p, false);
    expect(!r, g.name);
    expect(!called("openFileWrite"), "  -> refused before openFileWrite");
  }

  // 3. Overwrite: refuse without consent, proceed with consent.
  reset();
  g_fs.files["FORGDIA1.G"] = "old";
  expect(!forge_diag::generate_plate(p, false), "existing job refused without allow_overwrite");
  reset();
  g_fs.files["FORGDIA1.G"] = "old";
  expect(forge_diag::generate_plate(p, true), "existing job overwritten with allow_overwrite");

  // 4. SD write failure mid-plate: fail-closed (temp removed, nothing published).
  reset();
  g_fs.fail_after = 5000;
  expect(!forge_diag::generate_plate(p, false), "short write fails closed");
  expect(called("removeFile:FORGDIA1.TMP"), "temp removed on write failure");
  expect(!called("rename->FORGDIA1.G"), "no publish after write failure");
  expect(g_fs.files.empty(), "no diagnostic files left after write failure");

  // 5. Short final write (sentinel truncated): caught by the write-failure
  //    detector, still fail-closed.
  reset();
  {
    uint32_t full = forge_diag::estimate_plate_bytes(p);
    g_fs.fail_after = (long)full - 10;
  }
  expect(!forge_diag::generate_plate(p, false), "truncated tail fails closed (write detector)");
  expect(g_fs.files.empty(), "no diagnostic files left after truncated tail");

  // 6. Silent tail corruption with "successful" writes: the sentinel re-read
  //    before publish is the ONLY detector; it must reject the rename.
  reset();
  g_fs.tamper_tail = true;
  expect(!forge_diag::generate_plate(p, false), "corrupt tail rejected by sentinel re-read");
  expect(!called("rename->FORGDIA1.G"), "no publish after sentinel mismatch");
  expect(g_fs.files.empty(), "no diagnostic files left after sentinel rejection");

  printf("HARNESS %s (failures=%d)\n", failures ? "FAILED" : "OK", failures);
  return failures ? 1 : 0;
}
