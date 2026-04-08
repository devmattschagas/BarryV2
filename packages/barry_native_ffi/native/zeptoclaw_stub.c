#include "../src/zeptoclaw.h"

#include <stddef.h>
#include <string.h>

static int32_t safe_copy(char* out_buf, int32_t out_len, const char* src) {
  if (out_buf == NULL || src == NULL || out_len <= 0) {
    return -1;
  }

  const size_t src_len = strlen(src);
  if ((size_t)out_len <= src_len) {
    return -1;
  }

  memcpy(out_buf, src, src_len);
  out_buf[src_len] = '\0';
  return 0;
}

int32_t zeptoclaw_execute_script(const char* command, const char* payload_json, int32_t timeout_ms) {
  (void)payload_json;
  if (command == NULL || timeout_ms <= 0) {
    return -1;
  }
  return 0;
}

int32_t zeptoclaw_list_capabilities(char* out_buf, int32_t out_len) {
  static const char* caps = "status.read,sensors.scan,nav.lock";
  return safe_copy(out_buf, out_len, caps);
}

int32_t zeptoclaw_health_check() { return 1; }
int32_t zeptoclaw_cancel_task(int32_t task_id) { return task_id >= 0 ? 0 : -1; }

int32_t zeptoclaw_get_device_state(char* out_buf, int32_t out_len) {
  static const char* state = "{\"ok\":true}";
  return safe_copy(out_buf, out_len, state);
}
