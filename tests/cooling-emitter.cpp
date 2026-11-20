#define main generator_regressions
#include "main.cpp"
#undef main
int main(int argc, char **argv) {
  if (argc != 3) return 2;
  forge_diag::PlateParams p {40,200,(uint16_t)atoi(argv[2])};
  if (!forge_diag::generate_plate(p,false)) return 2;
  const auto &data = g_fs.files.at("FORGDIA1.G");
  FILE *out = fopen(argv[1],"wb"); if (!out) return 2;
  fwrite(data.data(),1,data.size(),out); return fclose(out) ? 2 : 0;
}
