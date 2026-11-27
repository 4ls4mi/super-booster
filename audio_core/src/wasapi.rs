use std::ffi::c_void;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use windows::core::{Interface, PCWSTR, PWSTR};
use windows::Win32::Devices::FunctionDiscovery::PKEY_Device_FriendlyName;
use windows::Win32::Foundation::{
    CloseHandle, E_FAIL, MAX_PATH, S_FALSE, S_OK, WAIT_FAILED,
};
use windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolume;
use windows::Win32::Media::Audio::Endpoints::IAudioMeterInformation;
use windows::Win32::Media::Audio::{
    eCapture, eConsole, eRender,
    IAudioCaptureClient, IAudioClient, IAudioRenderClient,
    IAudioSessionControl2, IAudioSessionManager2, IMMDevice, IMMDeviceEnumerator,
    ISimpleAudioVolume, MMDeviceEnumerator, AUDCLNT_BUFFERFLAGS_SILENT,
    AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM,
    AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY, AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
    AUDCLNT_STREAMFLAGS_LOOPBACK, DEVICE_STATE_ACTIVE, PKEY_AudioEndpoint_FormFactor, SPDIF,
    WAVEFORMATEX,
};
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CoTaskMemFree, CoUninitialize, CLSCTX_ALL,
    COINIT_MULTITHREADED, STGM_READ,
};
use windows::Win32::System::Threading::{
    CreateEventW, OpenProcess, QueryFullProcessImageNameW, WaitForSingleObject,
    PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION,
};

use crate::dsp::{DspProcessor, SharedAudioState};

const WAVE_FORMAT_IEEE_FLOAT: u16 = 3;

struct ComGuard(bool);
impl ComGuard {
    fn new() -> Self {
        unsafe {
            let hr = CoInitializeEx(None, COINIT_MULTITHREADED);
            Self(hr == S_OK || hr == S_FALSE)
        }
    }
}
impl Drop for ComGuard {
    fn drop(&mut self) {
        if self.0 {
            unsafe { CoUninitialize() };
        }
    }
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 4);
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push(' '),
            c => out.push(c),
        }
    }
    out
}

unsafe fn device_id(dev: &IMMDevice) -> String {
    match dev.GetId() {
        Ok(pw) => {
            let s = pw.to_string().unwrap_or_default();
            CoTaskMemFree(Some(pw.0 as *const c_void));
            s
        }
        Err(_) => String::new(),
    }
}

unsafe fn device_friendly_name(dev: &IMMDevice) -> String {
    let Ok(store) = dev.OpenPropertyStore(STGM_READ) else {
        return "Audio Device".to_string();
    };
    let Ok(prop) = store.GetValue(&PKEY_Device_FriendlyName) else {
        return "Audio Device".to_string();
    };
    let s = prop.to_string();
    if s.is_empty() {
        "Audio Device".to_string()
    } else {
        s
    }
}

unsafe fn find_device(
    enumerator: &IMMDeviceEnumerator,
    flow: windows::Win32::Media::Audio::EDataFlow,
    id_or_name: &str,
) -> windows::core::Result<IMMDevice> {
    if !id_or_name.is_empty() {
        let wide: Vec<u16> = id_or_name.encode_utf16().chain(Some(0)).collect();
        if let Ok(dev) = enumerator.GetDevice(PCWSTR(wide.as_ptr())) {
            if dev.GetState().ok() == Some(DEVICE_STATE_ACTIVE) {
                return Ok(dev);
            }
        }
        if let Ok(coll) = enumerator.EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE) {
            let count = coll.GetCount().unwrap_or(0);
            for i in 0..count {
                if let Ok(dev) = coll.Item(i) {
                    let fname = device_friendly_name(&dev);
                    if fname == id_or_name || fname.starts_with(id_or_name) {
                        return Ok(dev);
                    }
                }
            }
        }
    }
    enumerator.GetDefaultAudioEndpoint(flow, eConsole)
}

unsafe fn active_render_device(
    enumerator: &IMMDeviceEnumerator,
    id: &str,
) -> windows::core::Result<IMMDevice> {
    let endpoints = enumerator.EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE)?;
    for i in 0..endpoints.GetCount()? {
        let endpoint = endpoints.Item(i)?;
        if device_id(&endpoint) == id {
            return Ok(endpoint);
        }
    }
    Err(windows::core::Error::new(E_FAIL, "A selected audio device is unavailable"))
}

pub fn list_devices_json() -> String {
    let _com = ComGuard::new();
    unsafe {
        let Ok(enumerator) =
            CoCreateInstance::<_, IMMDeviceEnumerator>(&MMDeviceEnumerator, None, CLSCTX_ALL)
        else {
            return r#"{"outputs":[],"inputs":[]}"#.to_string();
        };

        let def_out_id = enumerator
            .GetDefaultAudioEndpoint(eRender, eConsole)
            .ok()
            .map(|d| device_id(&d))
            .unwrap_or_default();
        let def_in_id = enumerator
            .GetDefaultAudioEndpoint(eCapture, eConsole)
            .ok()
            .map(|d| device_id(&d))
            .unwrap_or_default();

        let collect = |flow, def_id: &str| -> Vec<String> {
            let mut items = Vec::new();
            if let Ok(coll) = enumerator.EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE) {
                let count = coll.GetCount().unwrap_or(0);
                for i in 0..count {
                    if let Ok(dev) = coll.Item(i) {
                        let id = device_id(&dev);
                        let name = device_friendly_name(&dev);
                        let is_def = !id.is_empty() && id == def_id;
                        let is_spdif = flow == eRender && dev.OpenPropertyStore(STGM_READ)
                            .and_then(|store| store.GetValue(&PKEY_AudioEndpoint_FormFactor))
                            .ok()
                            .and_then(|value| u32::try_from(&value).ok())
                            == Some(SPDIF.0 as u32);
                        items.push(format!(
                            r#"{{"id":"{}","name":"{}","isDefault":{},"isDigital":{}}}"#,
                            json_escape(&id),
                            json_escape(&name),
                            is_def,
                            is_spdif
                        ));
                    }
                }
            }
            items
        };

        let outs = collect(eRender, &def_out_id);
        let ins = collect(eCapture, &def_in_id);
        format!(
            r#"{{"outputs":[{}],"inputs":[{}]}}"#,
            outs.join(","),
            ins.join(",")
        )
    }
}

unsafe fn process_name_for_pid(pid: u32) -> String {
    if pid == 0 {
        return "System Sounds".to_string();
    }
    let Ok(handle) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) else {
        return format!("App ({pid})");
    };
    let mut buf = [0u16; MAX_PATH as usize];
    let mut len = buf.len() as u32;
    let ok = QueryFullProcessImageNameW(handle, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut len);
    let _ = CloseHandle(handle);
    if ok.is_err() || len == 0 {
        return format!("App ({pid})");
    }
    let path = String::from_utf16_lossy(&buf[..len as usize]);
    let file = path.rsplit('\\').next().unwrap_or(&path);
    let stem = file.strip_suffix(".exe").or_else(|| file.strip_suffix(".EXE")).unwrap_or(file);
    let mut chars = stem.chars();
    match chars.next() {
        Some(c) => c.to_uppercase().collect::<String>() + chars.as_str(),
        None => "App".to_string(),
    }
}

pub fn list_sessions_json() -> String {
    let _com = ComGuard::new();
    let self_pid = std::process::id();
    unsafe {
        let Ok(enumerator) =
            CoCreateInstance::<_, IMMDeviceEnumerator>(&MMDeviceEnumerator, None, CLSCTX_ALL)
        else {
            return "[]".to_string();
        };
        let Ok(dev) = enumerator.GetDefaultAudioEndpoint(eRender, eConsole) else {
            return "[]".to_string();
        };
        let Ok(mgr) = dev.Activate::<IAudioSessionManager2>(CLSCTX_ALL, None) else {
            return "[]".to_string();
        };
        let Ok(sess_enum) = mgr.GetSessionEnumerator() else {
            return "[]".to_string();
        };
        let count = sess_enum.GetCount().unwrap_or(0);
        let mut out = Vec::new();
        for i in 0..count {
            let Ok(ctrl) = sess_enum.GetSession(i) else { continue };
            let Ok(ctrl2) = ctrl.cast::<IAudioSessionControl2>() else { continue };
            let pid = ctrl2.GetProcessId().unwrap_or(0);
            if pid == self_pid {
                continue;
            }
            let is_sys = ctrl2.IsSystemSoundsSession() == S_OK;
            let raw_name = ctrl2
                .GetDisplayName()
                .ok()
                .and_then(|pw| {
                    let s = pw.to_string().unwrap_or_default();
                    CoTaskMemFree(Some(pw.0 as *const c_void));
                    if s.is_empty() || s.starts_with('@') { None } else { Some(s) }
                })
                .unwrap_or_else(|| {
                    if is_sys {
                        "System Sounds".to_string()
                    } else {
                        process_name_for_pid(pid)
                    }
                });

            let (vol, muted) = if let Ok(sv) = ctrl.cast::<ISimpleAudioVolume>() {
                (
                    sv.GetMasterVolume().unwrap_or(1.0),
                    sv.GetMute().map(|b| b.as_bool()).unwrap_or(false),
                )
            } else {
                (1.0, false)
            };

            let peak = ctrl
                .cast::<IAudioMeterInformation>()
                .ok()
                .and_then(|m| m.GetPeakValue().ok())
                .unwrap_or(0.0);

            let sid = ctrl2
                .GetSessionInstanceIdentifier()
                .ok()
                .map(|pw| {
                    let s = pw.to_string().unwrap_or_default();
                    CoTaskMemFree(Some(pw.0 as *const c_void));
                    s
                })
                .unwrap_or_default();

            out.push(format!(
                r#"{{"pid":{},"id":"{}","name":"{}","volume":{:.3},"muted":{},"peak":{:.3}}}"#,
                pid,
                json_escape(&sid),
                json_escape(&raw_name),
                vol,
                muted,
                peak
            ));
        }
        format!("[{}]", out.join(","))
    }
}

pub fn set_session_volume(pid: u32, volume: f32) -> bool {
    let _com = ComGuard::new();
    unsafe {
        let Ok(enumerator) =
            CoCreateInstance::<_, IMMDeviceEnumerator>(&MMDeviceEnumerator, None, CLSCTX_ALL)
        else { return false };
        let Ok(dev) = enumerator.GetDefaultAudioEndpoint(eRender, eConsole) else { return false };
        let Ok(mgr) = dev.Activate::<IAudioSessionManager2>(CLSCTX_ALL, None) else { return false };
        let Ok(sess_enum) = mgr.GetSessionEnumerator() else { return false };
        let count = sess_enum.GetCount().unwrap_or(0);
        let mut changed = false;
        for i in 0..count {
            if let Ok(ctrl) = sess_enum.GetSession(i) {
                if let Ok(ctrl2) = ctrl.cast::<IAudioSessionControl2>() {
                    if ctrl2.GetProcessId().unwrap_or(0) == pid {
                        if let Ok(sv) = ctrl.cast::<ISimpleAudioVolume>() {
                            if sv.SetMasterVolume(volume.clamp(0.0, 1.0), std::ptr::null()).is_ok() {
                                changed = true;
                            }
                        }
                    }
                }
            }
        }
        changed
    }
}

pub fn set_session_mute(pid: u32, mute: bool) -> bool {
    let _com = ComGuard::new();
    unsafe {
        let Ok(enumerator) =
            CoCreateInstance::<_, IMMDeviceEnumerator>(&MMDeviceEnumerator, None, CLSCTX_ALL)
        else { return false };
        let Ok(dev) = enumerator.GetDefaultAudioEndpoint(eRender, eConsole) else { return false };
        let Ok(mgr) = dev.Activate::<IAudioSessionManager2>(CLSCTX_ALL, None) else { return false };
        let Ok(sess_enum) = mgr.GetSessionEnumerator() else { return false };
        let count = sess_enum.GetCount().unwrap_or(0);
        let mut changed = false;
        for i in 0..count {
            if let Ok(ctrl) = sess_enum.GetSession(i) {
                if let Ok(ctrl2) = ctrl.cast::<IAudioSessionControl2>() {
                    if ctrl2.GetProcessId().unwrap_or(0) == pid {
                        if let Ok(sv) = ctrl.cast::<ISimpleAudioVolume>() {
                            if sv.SetMute(mute, std::ptr::null()).is_ok() {
                                changed = true;
                            }
                        }
                    }
                }
            }
        }
        changed
    }
}

unsafe fn master_endpoint(id: &str) -> windows::core::Result<IAudioEndpointVolume> {
    let enumerator: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
    let device = if id.is_empty() {
        enumerator.GetDefaultAudioEndpoint(eRender, eConsole)?
    } else {
        active_render_device(&enumerator, id)?
    };
    device.Activate(CLSCTX_ALL, None)
}

pub fn get_master_volume(id: &str) -> f32 {
    let _com = ComGuard::new();
    unsafe {
        let Ok(ep) = master_endpoint(id) else { return 1.0 };
        ep.GetMasterVolumeLevelScalar().unwrap_or(1.0)
    }
}

pub fn output_is_silenced(id: &str) -> bool {
    let _com = ComGuard::new();
    unsafe {
        let Ok(endpoint) = master_endpoint(id) else { return false };
        endpoint.GetMute().is_ok_and(|mute| mute.as_bool())
            || endpoint.GetMasterVolumeLevelScalar().is_ok_and(|volume| volume <= 0.0)
    }
}

pub fn output_peak(id: &str) -> f32 {
    let _com = ComGuard::new();
    (|| unsafe {
        let enumerator: IMMDeviceEnumerator =
            CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
        let device = active_render_device(&enumerator, id)?;
        let meter: IAudioMeterInformation = device.Activate(CLSCTX_ALL, None)?;
        meter.GetPeakValue()
    })().unwrap_or(0.0)
}

pub fn set_master_volume(id: &str, val: f32) -> bool {
    let _com = ComGuard::new();
    unsafe {
        let Ok(ep) = master_endpoint(id) else { return false };
        ep.SetMasterVolumeLevelScalar(val.clamp(0.0, 1.0), std::ptr::null()).is_ok()
    }
}

struct AudioEvent(windows::Win32::Foundation::HANDLE);

impl Drop for AudioEvent {
    fn drop(&mut self) {
        unsafe { let _ = CloseHandle(self.0); }
    }
}

fn stereo_float_format(sample_rate: u32) -> WAVEFORMATEX {
    WAVEFORMATEX {
        wFormatTag: WAVE_FORMAT_IEEE_FLOAT,
        nChannels: 2,
        nSamplesPerSec: sample_rate,
        nAvgBytesPerSec: sample_rate * 8,
        nBlockAlign: 8,
        wBitsPerSample: 32,
        cbSize: 0,
    }
}

pub fn run_engine_loop(
    state: Arc<SharedAudioState>,
    status_msg: Arc<Mutex<String>>,
    direct_mode: bool,
    in_device_id: String,
    out_device_id: String,
) {
    let _com = ComGuard::new();
    let set_status = |msg: &str| {
        if let Ok(mut g) = status_msg.lock() {
            *g = msg.to_string();
        }
    };

    let result: windows::core::Result<()> = (|| unsafe {
        let enumerator: IMMDeviceEnumerator =
            CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
        let out_dev = if direct_mode && !out_device_id.is_empty() {
            active_render_device(&enumerator, &out_device_id)?
        } else {
            find_device(&enumerator, eRender, &out_device_id)?
        };
        let out_name = device_friendly_name(&out_dev);

        let source = if direct_mode {
            if in_device_id.is_empty() {
                return Err(windows::core::Error::new(
                    E_FAIL, "Choose a silent Windows audio source in Settings",
                ));
            }
            let device = active_render_device(&enumerator, &in_device_id)?;
            if device_id(&device) == device_id(&out_dev) {
                return Err(windows::core::Error::new(
                    E_FAIL, "Choose different audio source and playback devices in Settings",
                ));
            }
            Some(device)
        } else {
            None
        };

        let render_client: IAudioClient = out_dev.Activate(CLSCTX_ALL, None)?;
        let mix_ptr = render_client.GetMixFormat()?;
        let sample_rate = (*mix_ptr).nSamplesPerSec;
        CoTaskMemFree(Some(mix_ptr as *const c_void));

        let fmt = stereo_float_format(sample_rate);
        let buffer_duration = 300_000_i64; // 30 ms in 100-ns units
        let conversion = AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY;
        render_client.Initialize(
            AUDCLNT_SHAREMODE_SHARED,
            conversion,
            buffer_duration,
            0,
            &fmt,
            None,
        )?;
        let render_buf_frames = render_client.GetBufferSize()?;
        let render_service: IAudioRenderClient = render_client.GetService()?;

        // The event stays open until after the capture client is released.
        let (capture_event, capture_client) = if let Some(source) = source {
            let event = AudioEvent(CreateEventW(None, false, false, None)?);
            let client: IAudioClient = source.Activate(CLSCTX_ALL, None)?;
            client.Initialize(
                AUDCLNT_SHAREMODE_SHARED,
                AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK | conversion,
                buffer_duration, 0, &fmt, None,
            )?;
            client.SetEventHandle(event.0)?;
            (Some(event), client)
        } else {
            let in_dev = find_device(&enumerator, eCapture, &in_device_id)?;
            let client: IAudioClient = in_dev.Activate(CLSCTX_ALL, None)?;
            client.Initialize(
                AUDCLNT_SHAREMODE_SHARED, conversion, buffer_duration, 0, &fmt, None,
            )?;
            (None, client)
        };
        let capture_service: IAudioCaptureClient = capture_client.GetService()?;

        capture_client.Start()?;
        render_client.Start()?;
        let mode = if direct_mode { "System Audio Boost" } else { "Device Routing" };
        set_status(&format!("{mode} active — {out_name}"));

        state.engine_running.store(true, Ordering::Release);
        state.engine_starting.store(false, Ordering::Release);
        let mut dsp = DspProcessor::new(sample_rate);
        let mut cap_scratch: Vec<f32> = Vec::with_capacity(4096);
        let mut out_scratch: Vec<f32> = Vec::with_capacity(4096);
        let mut idle_ticks = 0u32;

        while !state.stop_requested.load(Ordering::Acquire) {
            if let Some(event) = &capture_event {
                if WaitForSingleObject(event.0, 25) == WAIT_FAILED {
                    return Err(windows::core::Error::from_win32());
                }
            }
            cap_scratch.clear();
            loop {
                let pkt_len = capture_service.GetNextPacketSize()?;
                if pkt_len == 0 {
                    break;
                }
                let mut data_ptr: *mut u8 = std::ptr::null_mut();
                let mut frames_avail = 0u32;
                let mut flags = 0u32;
                capture_service.GetBuffer(&mut data_ptr, &mut frames_avail, &mut flags, None, None)?;
                if frames_avail > 0 {
                    let samples = frames_avail as usize * 2;
                    if (flags & AUDCLNT_BUFFERFLAGS_SILENT.0 as u32) != 0 || data_ptr.is_null() {
                        cap_scratch.resize(cap_scratch.len() + samples, 0.0);
                    } else {
                        let slice = std::slice::from_raw_parts(data_ptr.cast::<f32>(), samples);
                        cap_scratch.extend_from_slice(slice);
                    }
                }
                capture_service.ReleaseBuffer(frames_avail)?;
            }

            let cap_frames = cap_scratch.len() / 2;
            if cap_frames > 0 {
                idle_ticks = 0;
                out_scratch.resize(cap_frames * 2, 0.0);
                dsp.process_stereo(&cap_scratch, &mut out_scratch, &state);

                let padding = render_client.GetCurrentPadding()?;
                let avail = render_buf_frames.saturating_sub(padding) as usize;
                let write_frames = cap_frames.min(avail);
                if write_frames > 0 {
                    let out_ptr = render_service.GetBuffer(write_frames as u32)?;
                    let dst = std::slice::from_raw_parts_mut(out_ptr.cast::<f32>(), write_frames * 2);
                    // Keep the most recent frames if capture is ahead of render capacity.
                    let start = (cap_frames - write_frames) * 2;
                    dst.copy_from_slice(&out_scratch[start..]);
                    render_service.ReleaseBuffer(write_frames as u32, 0)?;
                }
            } else {
                idle_ticks = idle_ticks.saturating_add(1);
                if idle_ticks > 4 {
                    state.decay_meters();
                }
            }

            if capture_event.is_none() {
                std::thread::sleep(Duration::from_millis(5));
            }
        }

        let _ = capture_client.Stop();
        let _ = render_client.Stop();
        Ok(())
    })();

    state.decay_meters();
    if let Err(err) = result {
        set_status(&format!("Audio engine standby ({})", err.message()));
    } else if state.stop_requested.load(Ordering::Acquire) {
        set_status("Engine paused");
    }
    state.engine_running.store(false, Ordering::Release);
    state.engine_starting.store(false, Ordering::Release);
}
