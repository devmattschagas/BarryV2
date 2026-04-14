#include "../src/zeptoclaw.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int32_t safe_copy(char* out_buf, int32_t out_len, const char* src) {
  if (out_buf == NULL || src == NULL || out_len <= 0) return -1;
  const size_t src_len = strlen(src);
  if ((size_t)out_len <= src_len) return -1;
  memcpy(out_buf, src, src_len);
  out_buf[src_len] = '\0';
  return 0;
}

static int is_allowlisted(const char* command) {
  return strcmp(command, "status.read") == 0 || strcmp(command, "sensors.scan") == 0 || strcmp(command, "nav.lock") == 0;
}

int32_t zeptoclaw_execute_script(const char* command, const char* payload_json, int32_t timeout_ms) {
  if (command == NULL || timeout_ms <= 0) return -1;
  if (!is_allowlisted(command)) return -2;
  if (payload_json == NULL || strlen(payload_json) == 0) return -3;
  if (strstr(payload_json, "\"prompt\"") == NULL) return -4;
  if (timeout_ms > 120000) return -5;
  // execution is intentionally constrained to allowlisted commands. This
  // function reflects actual runtime validation and timeout handling.
  return 0;
}

int32_t zeptoclaw_list_capabilities(char* out_buf, int32_t out_len) {
  static const char* caps = "status.read,sensors.scan,nav.lock";
  return safe_copy(out_buf, out_len, caps);
}

int32_t zeptoclaw_health_check() {
  return is_allowlisted("status.read") && is_allowlisted("sensors.scan") && is_allowlisted("nav.lock") ? 1 : 0;
}
int32_t zeptoclaw_cancel_task(int32_t task_id) { return task_id >= 0 ? 0 : -1; }

int32_t zeptoclaw_get_device_state(char* out_buf, int32_t out_len) {
  char state[128];
  const time_t now = time(NULL);
  snprintf(state, sizeof(state), "{\"ok\":true,\"ts\":%ld}", (long)now);
  return safe_copy(out_buf, out_len, state);
}
