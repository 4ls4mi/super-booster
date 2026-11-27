mod dsp;
mod wasapi;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::JoinHandle;

use dsp::{SharedAudioState, SPECTRUM_BANDS};

struct EngineRuntime {
    state: Arc<SharedAudioState>,
    status: Arc<Mutex<String>>,
    worker: Mutex<Option<JoinHandle<()>>>,
}

static RUNTIME: OnceLock<EngineRuntime> = OnceLock::new();

fn runtime() -> &'static EngineRuntime {
    RUNTIME.get_or_init(|| EngineRuntime {
        state: Arc::new(SharedAudioState::new()),
        status: Arc::new(Mutex::new("Ready — System Audio Boost".to_string())),
        worker: Mutex::new(None),
    })
}

fn cstr_to_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(ptr).to_string_lossy().into_owned() }
}

fn to_c_string(s: String) -> *mut c_char {
    CString::new(s)
        .unwrap_or_else(|_| CString::new("").unwrap())
        .into_raw()
}

#[no_mangle]
pub extern "C" fn sb_init() {
    let _ = runtime();
}

#[no_mangle]
pub extern "C" fn sb_stop() {
    let rt = runtime();
    rt.state.stop_requested.store(true, Ordering::Release);
    if let Ok(mut guard) = rt.worker.lock() {
        if let Some(handle) = guard.take() {
            let _ = handle.join();
        }
    }
    rt.state.engine_running.store(false, Ordering::Release);
    rt.state.engine_starting.store(false, Ordering::Release);
}

#[no_mangle]
pub extern "C" fn sb_shutdown() {
    sb_stop();
}

#[no_mangle]
pub extern "C" fn sb_start_engine(
    direct_mode: bool,
    in_device_id: *const c_char,
    out_device_id: *const c_char,
) -> bool {
    sb_stop();
    let rt = runtime();
    rt.state.stop_requested.store(false, Ordering::Release);
    if let Ok(mut status) = rt.status.lock() {
        *status = "Connecting to Windows audio…".to_owned();
    }
    rt.state.engine_starting.store(true, Ordering::Release);

    let in_id = cstr_to_string(in_device_id);
    let out_id = cstr_to_string(out_device_id);
    let state = Arc::clone(&rt.state);
    let status = Arc::clone(&rt.status);

    let handle = std::thread::Builder::new()
        .name("sb-audio-engine".to_string())
        .spawn(move || {
            wasapi::run_engine_loop(state, status, direct_mode, in_id, out_id);
        });

    match handle {
        Ok(h) => {
            if let Ok(mut guard) = rt.worker.lock() {
                *guard = Some(h);
            }
            true
        }
        Err(error) => {
            if let Ok(mut status) = rt.status.lock() {
                *status = format!("Could not start the audio worker ({error})");
            }
            rt.state.engine_starting.store(false, Ordering::Release);
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn sb_is_starting() -> bool {
    runtime().state.engine_starting.load(Ordering::Acquire)
}

#[no_mangle]
pub extern "C" fn sb_is_running() -> bool {
    runtime().state.engine_running.load(Ordering::Acquire)
}

#[no_mangle]
pub extern "C" fn sb_set_gain_percent(percent: f32) {
    runtime().state.set_gain((percent / 100.0).clamp(0.0, 5.0));
}

#[no_mangle]
pub extern "C" fn sb_set_super_boost(enabled: bool) {
    runtime().state.super_boost.store(enabled, Ordering::Relaxed);
}

#[no_mangle]
pub extern "C" fn sb_set_limiter(enabled: bool) {
    runtime()
        .state
        .limiter_enabled
        .store(enabled, Ordering::Relaxed);
}

#[no_mangle]
pub extern "C" fn sb_set_bass_boost(amount: f32) {
    runtime().state.set_bass_boost(amount);
}

#[no_mangle]
pub extern "C" fn sb_get_meters(
    in_l: *mut f32,
    in_r: *mut f32,
    out_l: *mut f32,
    out_r: *mut f32,
    limiter_red: *mut f32,
) {
    let (il, ir, ol, or, red) = runtime().state.read_meters();
    unsafe {
        if !in_l.is_null() { *in_l = il; }
        if !in_r.is_null() { *in_r = ir; }
        if !out_l.is_null() { *out_l = ol; }
        if !out_r.is_null() { *out_r = or; }
        if !limiter_red.is_null() { *limiter_red = red; }
    }
}

#[no_mangle]
pub extern "C" fn sb_get_spectrum(out_ptr: *mut f32, max_len: usize) -> usize {
    if out_ptr.is_null() || max_len == 0 {
        return 0;
    }
    let count = max_len.min(SPECTRUM_BANDS);
    let slice = unsafe { std::slice::from_raw_parts_mut(out_ptr, count) };
    runtime().state.read_spectrum(slice);
    count
}

#[no_mangle]
pub extern "C" fn sb_get_status_message() -> *mut c_char {
    let msg = runtime()
        .status
        .lock()
        .map(|g| g.clone())
        .unwrap_or_else(|_| "Ready".to_string());
    to_c_string(msg)
}

#[no_mangle]
pub extern "C" fn sb_list_devices_json() -> *mut c_char {
    to_c_string(wasapi::list_devices_json())
}

#[no_mangle]
pub extern "C" fn sb_output_is_silenced(device_id: *const c_char) -> bool {
    wasapi::output_is_silenced(&cstr_to_string(device_id))
}

#[no_mangle]
pub extern "C" fn sb_output_peak(device_id: *const c_char) -> f32 {
    wasapi::output_peak(&cstr_to_string(device_id))
}

#[no_mangle]
pub extern "C" fn sb_list_sessions_json() -> *mut c_char {
    to_c_string(wasapi::list_sessions_json())
}

#[no_mangle]
pub extern "C" fn sb_set_session_volume(pid: u32, volume: f32) -> bool {
    wasapi::set_session_volume(pid, volume)
}

#[no_mangle]
pub extern "C" fn sb_set_session_mute(pid: u32, mute: bool) -> bool {
    wasapi::set_session_mute(pid, mute)
}

#[no_mangle]
pub extern "C" fn sb_get_master_volume(device_id: *const c_char) -> f32 {
    wasapi::get_master_volume(&cstr_to_string(device_id))
}

#[no_mangle]
pub extern "C" fn sb_set_master_volume(device_id: *const c_char, val: f32) -> bool {
    wasapi::set_master_volume(&cstr_to_string(device_id), val)
}

#[no_mangle]
pub extern "C" fn sb_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}
