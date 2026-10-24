#pragma once
#include <stdint.h>
#include <string.h>
#include <string>
#include <map>
#include <vector>
#define O_READ 0x01
struct FakeFS {
  std::map<std::string,std::string> files;
  std::string open_name;
  long fail_after = -1, written = 0; // write-failure injection point
  bool tamper_tail = false;          // corrupt file tail at closefile
  std::vector<std::string> calls;    // audit log for assertions
};
extern FakeFS g_fs;
class MediaFile {
public:
  std::string content, name; size_t pos = 0; bool is_open = false;
  bool open(MediaFile*, const char* n, int) {
    auto it = g_fs.files.find(n);
    if (it == g_fs.files.end()) return false;
    content = it->second; name = n; pos = 0; is_open = true;
    g_fs.calls.push_back(std::string("open:") + n); return true;
  }
  uint32_t fileSize() { return (uint32_t)content.size(); }
  bool seekSet(uint32_t p) { if (!is_open || p > content.size()) return false; pos = p; return true; }
  int read(void* buf, size_t n) {
    if (!is_open) return -1;
    size_t avail = content.size() - pos, k = n < avail ? n : avail;
    memcpy(buf, content.data() + pos, k); pos += k; return (int)k;
  }
  bool rename(MediaFile*, const char* n) {
    if (!is_open) return false;
    auto it = g_fs.files.find(name);
    if (it == g_fs.files.end()) return false;
    g_fs.files[n] = it->second; g_fs.files.erase(it); name = n;
    g_fs.calls.push_back(std::string("rename->") + n); return true;
  }
  void close() { is_open = false; }
};
class CardReader {
public:
  MediaFile workdir; bool mounted = true, file_open = false;
  int16_t write(void* data, int16_t n) {
    if (!file_open) return 0;
    if (g_fs.fail_after >= 0 && g_fs.written + n > g_fs.fail_after) {
      long room = g_fs.fail_after - g_fs.written; if (room < 0) room = 0;
      g_fs.files[g_fs.open_name].append((const char*)data, room);
      g_fs.written += room; return (int16_t)room; // short write
    }
    g_fs.files[g_fs.open_name].append((const char*)data, n);
    g_fs.written += n; return n;
  }
  void openFileWrite(const char* n) {
    g_fs.calls.push_back(std::string("openFileWrite:") + n);
    g_fs.open_name = n; g_fs.files[n] = ""; file_open = true; g_fs.written = 0;
  }
  bool isFileOpen() { return file_open; }
  void closefile(bool = false) {
    g_fs.calls.push_back("closefile"); file_open = false;
    if (g_fs.tamper_tail) { // bit-rot on the card: writes "succeeded" but the tail is garbage
      std::string& c = g_fs.files[g_fs.open_name];
      if (c.size() > 4) c.replace(c.size() - 4, 4, "XXXX");
    }
  }
  void removeFile(const char* n) { g_fs.calls.push_back(std::string("removeFile:") + n); g_fs.files.erase(n); }
  bool fileExists(const char* n) { return g_fs.files.count(n) > 0; }
  bool isMounted() { return mounted; }
  MediaFile& getWorkDir() { return workdir; }
};
extern CardReader card;
