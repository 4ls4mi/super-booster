#pragma once

#include <cstddef>
#include <cstdint>

extern "C" {
void sb_init();
void sb_stop();
void sb_shutdown();
bool sb_start_engine(bool direct_mode, const char* in_device_id, const char* out_device_id);
bool sb_is_running();
bool sb_is_starting();
void sb_set_gain_percent(float percent);
void sb_set_super_boost(bool enabled);
void sb_set_limiter(bool enabled);
void sb_set_bass_boost(float amount);
void sb_get_meters(float* in_l, float* in_r, float* out_l, float* out_r, float* limiter_red);
size_t sb_get_spectrum(float* out_ptr, size_t max_len);
char* sb_get_status_message();
char* sb_list_devices_json();
bool sb_output_is_silenced(const char* device_id);
float sb_output_peak(const char* device_id);
char* sb_list_sessions_json();
bool sb_set_session_volume(uint32_t pid, float volume);
bool sb_set_session_mute(uint32_t pid, bool mute);
float sb_get_master_volume(const char* device_id);
bool sb_set_master_volume(const char* device_id, float val);
void sb_free_string(char* ptr);
}
