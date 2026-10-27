// Host harness: runs the REAL forge_diag::build_report (byte-identical copy of the
// tree file, FORGE_TEST_BUILD on) against stubbed state and dumps lines for rendering.
#include "src/sd/cardreader.h"
#include "src/MarlinCore.h"
#include "src/module/planner.h"
#include "src/module/temperature.h"
#include "src/module/probe.h"
#include "src/lcd/marlinui.h"
FakeFS g_fs; CardReader card; MarlinStub marlin; PlannerStub planner; TempStub thermalManager; UIStub ui; ProbeStub probe;
RecoveryStub recovery;
char* dtostrf(double v, signed char, unsigned char prec, char* buf){ sprintf(buf,"%.*f",(int)prec,v); return buf; }
unsigned long millis(){ return 754321UL; }
#include "src/e3v3se/forge_diag.h"
static int fails=0;
static void expect(bool c,const char*l){ printf("%s %s\n",c?"PASS":"FAIL",l); if(!c) fails++; }
static unsigned n_lines; static char L[FORGE_REPORT_MAX_LINES][FORGE_REPORT_WIDTH];
static void dump(const char*tag){
  n_lines = forge_diag::build_report(L, FORGE_REPORT_MAX_LINES);
  char fn[64]; snprintf(fn,sizeof fn,"/tmp/forge-report-%s.txt",tag); FILE*f=fopen(fn,"w");
  for(unsigned i=0;i<n_lines;i++) fprintf(f,"%s\n",L[i]); fclose(f);
  printf("== %s (%u lines)\n",tag,n_lines); for(unsigned i=0;i<n_lines;i++) printf("%s\n",L[i]);
}
int main(){
  recovery.enabled=false;
  size_t calls_before;
  dump("idle"); expect(n_lines>=14,"idle: full report emitted");
  expect(strstr(L[6],"[off]")!=0 && !strstr(L[6],"[ON]"),"idle: heaters off shown");
  calls_before=g_fs.calls.size(); dump("idle2"); expect(g_fs.calls.size()==calls_before,"report makes no SD calls when building");
  for(unsigned i=0;i<n_lines;i++) expect(strlen(L[i])<=32,"line width <= 32 chars");
  // heaters on
  thermalManager.tn=210; thermalManager.tb=65; thermalManager.hn=150; thermalManager.hb=40; dump("heating");
  expect(strstr(L[6],"[ON]")!=0,"heating: shows [ON]");
  // sensor fault (open thermistor reads very high / zero)
  thermalManager=TempStub(); thermalManager.hn=0; dump("sensorfault"); expect(strstr(L[4],"[check]")!=0 && strstr(L[5],"[ok]")!=0,"nozzle sensor 0C flags [check], bed stays [ok]");
  thermalManager=TempStub(); thermalManager.hb=130; dump("bedhot"); expect(strstr(L[5],"[check]")!=0,"bed over max flags [check]");
  // no sd
  thermalManager=TempStub(); card.mounted=false; dump("nosd"); expect(strstr(L[3],"[none]")!=0 && strstr(L[13],"[no sd]")!=0 ,"no sd shown");
  // sd with stale tmp and job file
  card.mounted=true; g_fs.files["FORGDIA1.TMP"]="x"; g_fs.files["FORGDIA1.G"]="x"; recovery.enabled=true; planner.leveling_active=false; dump("sdfiles");
  bool stale=false,leveloff=false,plron=false; for(unsigned i=0;i<n_lines;i++){ if(strstr(L[i],"[STALE]")) stale=true; if(strstr(L[i],"leveling [off]")) leveloff=true; if(strstr(L[i],"plr [on]")) plron=true; }
  expect(stale,"stale tmp flagged"); expect(leveloff,"leveling off shown"); expect(plron,"plr on shown");
  // read-only: no SD writes, no job gating changes
  bool wrote=false; for(auto&c:g_fs.calls) if(c.rfind("openFileWrite",0)==0||c.rfind("removeFile",0)==0||c.rfind("rename",0)==0) wrote=true;
  expect(!wrote,"report performed no SD write/remove/rename");
  printf("%s\n", fails? "REPORT HARNESS FAIL":"REPORT HARNESS OK"); return fails?1:0;
}
