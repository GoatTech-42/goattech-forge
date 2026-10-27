#pragma once
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdarg.h>
#include <stdlib.h>
#define FORGE_TEST_BUILD 1
#define PSTR(s) s
#define SERIAL_ECHOLNPGM(s) do {} while(0)
#define SERIAL_ECHOPGM(s) do {} while(0)
#define SERIAL_ECHO(x) do {} while(0)
#define constrain(x,a,b) ((x)<(a)?(a):((x)>(b)?(b):(x)))
#define HEATER_0_MINTEMP 0
#define HEATER_0_MAXTEMP 310
#define BED_MINTEMP 0
#define BED_MAXTEMP 125
#define BOARD_INFO_NAME "CR4NS200320C13"
#define SHORT_BUILD_VERSION "v2.1.x Krasnaya 5"
#define THERMAL_PROTECTION_HOTENDS 1
#define THERMAL_PROTECTION_BED 1
#define S_CURVE_ACCELERATION 1
#define POWER_LOSS_RECOVERY 1
#define HAS_LEVELING 1
#define ENABLED(x) (x)
char* dtostrf(double v, signed char w, unsigned char prec, char* buf);
unsigned long millis();
