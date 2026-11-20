// Compile the real Forge value handler with display and encoder I/O stubbed.
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include "src/module/temperature.h"
TempStub thermalManager;
#define LIMIT(v, lo, hi) ((v) = std::min<float>(std::max<float>((v), (lo)), (hi)))
#define MBASE(v) (v)
enum { ENCODER_DIFF_NO, ENCODER_DIFF_TURN, ENCODER_DIFF_ENTER };
using ENCODER_DiffState = int;
enum { ForgeDiagnostics, ForgeDiag_Nozzle, ForgeDiag_TempN, ForgeDiag_TempB };
enum { font8x16, Color_White, Color_Bg_Black, Select_Color, VALUERANGE_X,
       FORGEDIAG_CASE_NOZZLE, FORGEDIAG_CASE_TEMPN, FORGEDIAG_CASE_TEMPB };
struct { float ForgeDiag_scaled; } HMI_ValueStruct;
struct { bool enabled; } EncoderRate;
struct { uint16_t nozzle_x100, temp_nozzle, temp_bed; } forge_diag_params;
bool forge_diag_overwrite_pending;
int checkkey, encoder;
float displayed;
int reviews;
int get_encoder_state() { return encoder; }
bool Apply_Encoder(int state, float&) { return state == ENCODER_DIFF_ENTER; }
template<typename... T> void DWIN_Draw_IntValue(T... values) { ((displayed = values), ...); }
template<typename... T> void DWIN_Draw_FloatValue(T... values) { ((displayed = values), ...); }
void Draw_ForgeDiagReview() { ++reviews; }
void DWIN_UpdateLCD() {}

// The runner inserts the unmodified HMI_ForgeDiagnostics_Values here.
#include "handler.cpp"

int main() {
  int failures = 0;
  const struct { int requested, want; } cases[] = {
    { 114, 114 }, { 115, 115 }, { 116, 115 }, { 125, 115 }
  };
  for (const auto &bed : cases) {
    const int requested = bed.requested;
    for (const int state : { ENCODER_DIFF_TURN, ENCODER_DIFF_ENTER }) {
      checkkey = ForgeDiag_TempB;
      encoder = state;
      HMI_ValueStruct.ForgeDiag_scaled = requested;
      forge_diag_params.temp_bed = 60;
      forge_diag_overwrite_pending = true;
      displayed = -1;
      reviews = 0;
      EncoderRate.enabled = true;
      HMI_ForgeDiagnostics_Values();
      bool ok = HMI_ValueStruct.ForgeDiag_scaled == bed.want && displayed == bed.want;
      if (state == ENCODER_DIFF_ENTER)
        ok = ok && forge_diag_params.temp_bed == bed.want && !forge_diag_overwrite_pending
                && checkkey == ForgeDiagnostics && !EncoderRate.enabled && reviews == 1;
      else
        ok = ok && forge_diag_params.temp_bed == 60 && forge_diag_overwrite_pending
                && checkkey == ForgeDiag_TempB && reviews == 0;
      printf("%s bed menu: requested=%d state=%d value=%.0f displayed=%.0f confirmed=%u\n",
             ok ? "PASS" : "FAIL", requested, state, HMI_ValueStruct.ForgeDiag_scaled,
             displayed, (unsigned)forge_diag_params.temp_bed);
      failures += !ok;
    }
  }
  return failures ? 1 : 0;
}
