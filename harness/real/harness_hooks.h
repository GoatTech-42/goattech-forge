#pragma once
// Values the host stubs expose to the harness driver.
#include <stdint.h>
extern uint32_t harness_millis;  // returned by millis()
extern uint16_t harness_adc;     // returned by MarlinHAL::adc_value()
