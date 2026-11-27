use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};

pub const SPECTRUM_BANDS: usize = 24;

/// Lock-free shared parameters and real-time metering between audio thread and UI/C++.
pub struct SharedAudioState {
    gain_bits: AtomicU32,
    bass_boost_bits: AtomicU32,
    pub super_boost: AtomicBool,
    pub limiter_enabled: AtomicBool,
    pub engine_running: AtomicBool,
    pub engine_starting: AtomicBool,
    pub stop_requested: AtomicBool,

    in_peak_l: AtomicU32,
    in_peak_r: AtomicU32,
    out_peak_l: AtomicU32,
    out_peak_r: AtomicU32,
    limiter_reduction: AtomicU32,
    spectrum: [AtomicU32; SPECTRUM_BANDS],
}

impl SharedAudioState {
    pub fn new() -> Self {
        Self {
            gain_bits: AtomicU32::new(1.0_f32.to_bits()),
            bass_boost_bits: AtomicU32::new(0.0_f32.to_bits()),
            super_boost: AtomicBool::new(false),
            limiter_enabled: AtomicBool::new(true),
            engine_running: AtomicBool::new(false),
            engine_starting: AtomicBool::new(false),
            stop_requested: AtomicBool::new(false),
            in_peak_l: AtomicU32::new(0.0_f32.to_bits()),
            in_peak_r: AtomicU32::new(0.0_f32.to_bits()),
            out_peak_l: AtomicU32::new(0.0_f32.to_bits()),
            out_peak_r: AtomicU32::new(0.0_f32.to_bits()),
            limiter_reduction: AtomicU32::new(0.0_f32.to_bits()),
            spectrum: std::array::from_fn(|_| AtomicU32::new(0.0_f32.to_bits())),
        }
    }

    pub fn set_gain(&self, gain: f32) {
        self.gain_bits
            .store(gain.clamp(0.0, 5.0).to_bits(), Ordering::Relaxed);
    }

    pub fn gain(&self) -> f32 {
        f32::from_bits(self.gain_bits.load(Ordering::Relaxed))
    }

    pub fn set_bass_boost(&self, amount: f32) {
        self.bass_boost_bits
            .store(amount.clamp(0.0, 1.0).to_bits(), Ordering::Relaxed);
    }

    pub fn bass_boost(&self) -> f32 {
        f32::from_bits(self.bass_boost_bits.load(Ordering::Relaxed))
    }

    pub fn store_meters(&self, in_l: f32, in_r: f32, out_l: f32, out_r: f32, red: f32) {
        self.in_peak_l.store(in_l.to_bits(), Ordering::Relaxed);
        self.in_peak_r.store(in_r.to_bits(), Ordering::Relaxed);
        self.out_peak_l.store(out_l.to_bits(), Ordering::Relaxed);
        self.out_peak_r.store(out_r.to_bits(), Ordering::Relaxed);
        self.limiter_reduction.store(red.to_bits(), Ordering::Relaxed);
    }

    pub fn read_meters(&self) -> (f32, f32, f32, f32, f32) {
        (
            f32::from_bits(self.in_peak_l.load(Ordering::Relaxed)),
            f32::from_bits(self.in_peak_r.load(Ordering::Relaxed)),
            f32::from_bits(self.out_peak_l.load(Ordering::Relaxed)),
            f32::from_bits(self.out_peak_r.load(Ordering::Relaxed)),
            f32::from_bits(self.limiter_reduction.load(Ordering::Relaxed)),
        )
    }

    pub fn store_spectrum(&self, bands: &[f32; SPECTRUM_BANDS]) {
        for (i, &val) in bands.iter().enumerate() {
            let prev = f32::from_bits(self.spectrum[i].load(Ordering::Relaxed));
            // Smooth visual decay
            let smoothed = if val > prev {
                prev * 0.35 + val * 0.65
            } else {
                prev * 0.82 + val * 0.18
            };
            self.spectrum[i].store(smoothed.clamp(0.0, 1.0).to_bits(), Ordering::Relaxed);
        }
    }

    pub fn read_spectrum(&self, out: &mut [f32]) {
        let n = out.len().min(SPECTRUM_BANDS);
        for (dst, src) in out[..n].iter_mut().zip(self.spectrum[..n].iter()) {
            *dst = f32::from_bits(src.load(Ordering::Relaxed));
        }
    }

    pub fn decay_meters(&self) {
        let (il, ir, ol, or, red) = self.read_meters();
        self.store_meters(il * 0.82, ir * 0.82, ol * 0.82, or * 0.82, red * 0.8);
        let zeros = [0.0_f32; SPECTRUM_BANDS];
        self.store_spectrum(&zeros);
    }
}

/// Real-time audio DSP processor (no heap allocations during processing).
pub struct DspProcessor {
    sample_rate: f32,
    lp_l: f32,
    lp_r: f32,
    env_gain: f32,
    smoothed_gain: f32,
    band_phases: [f32; SPECTRUM_BANDS],
    band_energies: [f32; SPECTRUM_BANDS],
}

impl DspProcessor {
    pub fn new(sample_rate: u32) -> Self {
        Self {
            sample_rate: (sample_rate.max(8000)) as f32,
            lp_l: 0.0,
            lp_r: 0.0,
            env_gain: 1.0,
            smoothed_gain: 1.0,
            band_phases: [0.0; SPECTRUM_BANDS],
            band_energies: [0.0; SPECTRUM_BANDS],
        }
    }

    /// Computes soft-knee limiting + optional SuperBoost compression + low-shelf bass.
    #[inline]
    fn shape_sample(&mut self, x: f32, target_gain: f32, super_boost: bool, limiter: bool, bass: f32, is_left: bool) -> (f32, f32) {
        // 1-pole low-pass ~115 Hz for bass enhancement
        let alpha = (2.0 * std::f32::consts::PI * 115.0 / self.sample_rate).min(0.45);
        let lp = if is_left {
            self.lp_l += alpha * (x - self.lp_l);
            self.lp_l
        } else {
            self.lp_r += alpha * (x - self.lp_r);
            self.lp_r
        };

        let shaped_in = x + lp * (bass * 1.45);
        let mut boosted = shaped_in * target_gain;

        // SuperBoost mode applies gentle upward compression so quiet voices/audio stand out
        if super_boost {
            let abs_v = boosted.abs();
            if abs_v > 0.001 && abs_v < 0.65 {
                let lift = 1.0 + 0.45 * (1.0 - abs_v / 0.65);
                boosted *= lift;
            }
        }

        if limiter {
            // Smooth envelope follower + tanh soft-knee saturation at 0.94 ceiling
            let abs_b = boosted.abs();
            let desired_scale = if abs_b > 0.88 { 0.88 / abs_b } else { 1.0 };
            if desired_scale < self.env_gain {
                self.env_gain = self.env_gain * 0.85 + desired_scale * 0.15;
            } else {
                self.env_gain = self.env_gain * 0.9992 + desired_scale * 0.0008;
            }
            let controlled = boosted * self.env_gain;
            let soft = (controlled / 0.96).tanh() * 0.96;
            let reduction = (1.0 - self.env_gain).clamp(0.0, 1.0);
            (soft.clamp(-0.99, 0.99), reduction)
        } else {
            let clipped = boosted.clamp(-1.0, 1.0);
            let reduction = if boosted.abs() > 1.0 { (boosted.abs() - 1.0).min(1.0) } else { 0.0 };
            (clipped, reduction)
        }
    }

    /// Processes stereo interleaved f32 audio.
    pub fn process_stereo(
        &mut self,
        input: &[f32],
        output: &mut [f32],
        state: &SharedAudioState,
    ) {
        let frames = (input.len() / 2).min(output.len() / 2);
        if frames == 0 {
            return;
        }

        let requested_gain = state.gain();
        let super_boost = state.super_boost.load(Ordering::Relaxed);
        let limiter = state.limiter_enabled.load(Ordering::Relaxed);
        let bass = state.bass_boost();

        let mut in_pk_l = 0.0_f32;
        let mut in_pk_r = 0.0_f32;
        let mut out_pk_l = 0.0_f32;
        let mut out_pk_r = 0.0_f32;
        let mut max_red = 0.0_f32;

        // Lightweight logarithmically spaced Goertzel/oscillator band tracker for 24-band live spectrum
        self.band_energies.fill(0.0);

        for f in 0..frames {
            let l = input[f * 2];
            let r = input[f * 2 + 1];
            in_pk_l = in_pk_l.max(l.abs());
            in_pk_r = in_pk_r.max(r.abs());

            // Smooth gain changes to prevent zipper noise while sliding
            self.smoothed_gain = self.smoothed_gain * 0.995 + requested_gain * 0.005;

            let (ol, red_l) = if self.smoothed_gain <= 0.0005 {
                (0.0, 0.0)
            } else {
                self.shape_sample(l, self.smoothed_gain, super_boost, limiter, bass, true)
            };
            let (or, red_r) = if self.smoothed_gain <= 0.0005 {
                (0.0, 0.0)
            } else {
                self.shape_sample(r, self.smoothed_gain, super_boost, limiter, bass, false)
            };

            output[f * 2] = ol;
            output[f * 2 + 1] = or;
            out_pk_l = out_pk_l.max(ol.abs());
            out_pk_r = out_pk_r.max(or.abs());
            max_red = max_red.max(red_l.max(red_r));

            // Subsample spectrum tracking every 4th frame for low CPU cost
            if (f & 3) == 0 {
                let mono = (l + r) * 0.5;
                for b in 0..SPECTRUM_BANDS {
                    // Exponentially spaced center freqs 45Hz .. 12kHz
                    let t = b as f32 / (SPECTRUM_BANDS - 1) as f32;
                    let freq = 45.0 * (260.0_f32).powf(t);
                    let step = 4.0 * 2.0 * std::f32::consts::PI * freq / self.sample_rate;
                    self.band_phases[b] = (self.band_phases[b] + step) % (2.0 * std::f32::consts::PI);
                    let proj = (mono * self.band_phases[b].sin()).abs();
                    self.band_energies[b] += proj;
                }
            }
        }

        let norm_div = ((frames / 4).max(1)) as f32;
        let boost_vis = self.smoothed_gain.clamp(0.4, 3.0);
        for b in 0..SPECTRUM_BANDS {
            self.band_energies[b] = ((self.band_energies[b] / norm_div) * 3.8 * boost_vis).clamp(0.0, 1.0);
        }

        state.store_meters(in_pk_l, in_pk_r, out_pk_l, out_pk_r, max_red);
        state.store_spectrum(&self.band_energies);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn soft_limiter_keeps_500_percent_within_safe_bounds() {
        let state = SharedAudioState::new();
        state.set_gain(5.0);
        state.limiter_enabled.store(true, Ordering::Relaxed);
        state.super_boost.store(true, Ordering::Relaxed);
        let mut dsp = DspProcessor::new(48000);
        let input: Vec<f32> = (0..1024)
            .map(|i| ((i as f32) * 0.08).sin() * 0.8)
            .collect();
        let mut output = vec![0.0_f32; 1024];
        dsp.process_stereo(&input, &mut output, &state);
        assert!(output.iter().all(|&s| s >= -0.99 && s <= 0.99));
        let (_, _, out_l, _, _) = state.read_meters();
        assert!(out_l > 0.5);
    }

    #[test]
    fn routed_boost_outputs_the_full_signal_once() {
        let state = SharedAudioState::new();
        state.limiter_enabled.store(false, Ordering::Relaxed);
        let mut dsp = DspProcessor::new(48_000);
        let input = [0.05, -0.05].repeat(2048);
        let mut output = vec![0.0; input.len()];
        dsp.process_stereo(&input, &mut output, &state);
        assert_eq!(output, input);

        state.set_gain(5.0);
        dsp.process_stereo(&input, &mut output, &state);
        assert!((output[4094] - 0.25).abs() < 0.001);
        assert!((output[4095] + 0.25).abs() < 0.001);
    }
}
