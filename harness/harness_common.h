#pragma once
#include <stdio.h>
#include <stdint.h>
#define PSTR(s) s
#define SERIAL_ECHOLNPGM(s) do { printf("%s\n", s); } while(0)
#define SERIAL_ECHOPGM(s) do { printf("%s", s); } while(0)
#define SERIAL_ECHO(x) do { printf("%u", (unsigned)(x)); } while(0)
#define constrain(x,a,b) ((x)<(a)?(a):((x)>(b)?(b):(x)))
char* dtostrf(double v, signed char w, unsigned char prec, char* buf);
