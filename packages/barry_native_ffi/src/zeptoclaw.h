#ifndef ZEPTOCLAW_H
#define ZEPTOCLAW_H
#include <stdint.h>

int32_t zeptoclaw_execute_script(const char* command, const char* payload_json, int32_t timeout_ms);
int32_t zeptoclaw_list_capabilities(char* out_buf, int32_t out_len);
int32_t zeptoclaw_health_check();
int32_t zeptoclaw_cancel_task(int32_t task_id);
int32_t zeptoclaw_get_device_state(char* out_buf, int32_t out_len);

double barry_vad_infer(const int16_t* pcm16, int32_t length);

#endif
