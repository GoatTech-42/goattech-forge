// Execute the real SD start/resume function with file I/O faults injected.
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include "forge_diag.h"
#define FILENAME_LENGTH 13
#define PSTR(s) s
#define SERIAL_ECHOLNPGM(s) ((void)0)
#define TERN_(feature, statement) statement
struct { void set_status_P(const char*) {} } ui;
struct FileStub {
  std::string name = FORGE_DIAG_JOB_NAME, content;
  uint32_t pos = 0;
  int seeks = 0, reads = 0, fail_seek = 0;
  bool fail_read = false, short_read = false, cluster_valid = true;
  bool isOpen() { return true; }
  void getDosName(char *out) { std::strcpy(out, name.c_str()); }
  bool seekSet(uint32_t target) {
    ++seeks;
    if (seeks == fail_seek) { cluster_valid = false; return false; }
    if (target > content.size()) return false;
    pos = target; cluster_valid = true; return true;
  }
  int read(void *out, uint32_t count) {
    ++reads;
    if (fail_read) return -1;
    uint32_t n = std::min<uint32_t>(count, content.size() - pos);
    if (short_read && n) --n;
    std::memcpy(out, content.data() + pos, n); pos += n;
    return n;
  }
};
struct CardReader {
  FileStub myfile;
  uint32_t filesize = 0, sdpos = 0;
  bool mounted = true;
  struct { bool sdprinting = false, sdprintdone = true; } flag;
  int flushes = 0;
  bool isMounted() { return mounted; }
  bool isFileOpen() { return myfile.isOpen(); }
  void flush_presort() { ++flushes; }
  void startOrResumeFilePrinting();
};
#include "start-function.cpp"

static int failures = 0;
static void check(bool ok, const char *label) {
  printf("%s start guard: %s\n", ok ? "PASS" : "FAIL", label);
  failures += !ok;
}
static CardReader sample() {
  CardReader c;
  c.myfile.content = std::string(220, ' ');
  c.myfile.content += FORGE_DIAG_SENTINEL "\n";
  c.filesize = c.myfile.content.size();
  c.sdpos = c.myfile.pos = 32; // paused mid-file, not the easy seek-to-zero case
  return c;
}
int main() {
  auto c = sample();
  c.startOrResumeFilePrinting();
  check(c.flag.sdprinting && !c.flag.sdprintdone && c.flushes == 1,
        "valid diagnostic starts");
  check(c.myfile.pos == c.sdpos && c.myfile.cluster_valid,
        "successful verification restores the paused cursor");
  c = sample(); c.myfile.fail_seek = 1;
  // A stale sentinel at the old cursor must not mask failure to seek the tail.
  c.myfile.content.replace(c.sdpos, std::strlen(FORGE_DIAG_SENTINEL), FORGE_DIAG_SENTINEL);
  c.startOrResumeFilePrinting();
  check(!c.flag.sdprinting && c.flag.sdprintdone && c.flushes == 0,
        "tail seek failure refuses start");
  check(c.myfile.reads == 0 && c.myfile.seeks == 2 && c.myfile.cluster_valid,
        "failed tail seek skips read but still attempts cursor restoration");
  c = sample(); c.myfile.fail_seek = 2;
  c.startOrResumeFilePrinting();
  check(!c.flag.sdprinting && c.flag.sdprintdone && c.flushes == 0,
        "restore seek failure refuses start");
  c = sample(); c.myfile.fail_read = true;
  c.startOrResumeFilePrinting();
  check(!c.flag.sdprinting && c.myfile.pos == c.sdpos,
        "read error refuses start and restores cursor");
  c = sample(); c.myfile.short_read = true;
  c.startOrResumeFilePrinting();
  check(!c.flag.sdprinting && c.myfile.pos == c.sdpos,
        "short tail read refuses start and restores cursor");
  c = sample(); c.myfile.name = FORGE_DIAG_TEMP_NAME;
  c.startOrResumeFilePrinting();
  check(!c.flag.sdprinting && c.myfile.seeks == 0, "temp name always refused");
  c = sample(); c.myfile.name = "NORMAL.G";
  c.startOrResumeFilePrinting();
  check(c.flag.sdprinting && c.myfile.seeks == 0, "ordinary job bypass unchanged");
  c = sample(); c.myfile.content.replace(c.filesize - std::strlen(FORGE_DIAG_SENTINEL) - 1,
                                       std::strlen(FORGE_DIAG_SENTINEL), std::string(std::strlen(FORGE_DIAG_SENTINEL), 'x'));
  c.startOrResumeFilePrinting();
  check(!c.flag.sdprinting && c.myfile.pos == c.sdpos, "missing sentinel refused");
  c = sample(); c.myfile.content += "G1 X1\n"; c.filesize = c.myfile.content.size();
  c.startOrResumeFilePrinting();
  check(c.flag.sdprinting && c.myfile.pos == c.sdpos,
        "presence-only sentinel policy unchanged, not exact-final-line validation");
  return failures ? 1 : 0;
}
