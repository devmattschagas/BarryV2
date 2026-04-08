#include "../src/zeptoclaw.h"
#include <string.h>

int32_t zeptoclaw_execute_script(const char* command, const char* payload_json, int32_t timeout_ms) {
  (void)payload_json;
  if (command == NULL || timeout_ms <= 0) return -1;
  return 0;
}

int32_t zeptoclaw_list_capabilities(char* out_buf, int32_t out_len) {
  const char* caps = "status.read,sensors.scan,nav.lock";
  if (out_len < (int32_t)strlen(caps) + 1) return -1;
  strcpy(out_buf, caps);
  return 0;
}

int32_t zeptoclaw_health_check() { return 1; }
int32_t zeptoclaw_cancel_task(int32_t task_id) { return task_id >= 0 ? 0 : -1; }

int32_t zeptoclaw_get_device_state(char* out_buf, int32_t out_len) {
  const char* state = "{\"ok\":true}";
  if (out_len < (int32_t)strlen(state) + 1) return -1;
  strcpy(out_buf, state);
  return 0;
}
