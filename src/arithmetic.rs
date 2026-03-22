use crate::utils::{EncodeResult, Range, Scratch};

#[cfg(test)]
use crate::utils::ZoomResult;

#[cfg(target_family = "wasm")]
use wasm_bindgen::prelude::wasm_bindgen;

#[cfg(target_family = "wasm")]
#[cfg_attr(target_family = "wasm", wasm_bindgen)]
extern "C" {
    // encode bit result callback
    fn bit_encoded(result: u64, result_count: u32);

    // a handler for places where we should be panicking
    fn error_handler(error_code: u32, p1: u32, p2: u32);

    // javascript logging functions
    #[cfg(feature = "js_debug")]
    fn log32_1(a: u32);
    #[cfg(feature = "js_debug")]
    fn log32_2(a: u32, b: u32);
    #[cfg(feature = "js_debug")]
    fn log32_3(a: u32, b: u32, c: u32);
}

#[repr(u32)]
pub enum EncodeError {
    BitSetWithProbabilityZero = 1,
    BitUnsetWithProbabilityOne = 2,
    ProbabilityGreaterThanOne = 3,
    ProbabilityLessThanZero = 4,
}

pub struct Encoder {
    scratch: Scratch,
    range: Range,
}

impl Encoder {
    #[cfg_attr(target_family = "wasm", inline(always))]
    pub fn new() -> Encoder {
        Encoder {
            scratch: Scratch::new(),
            range: Range::new(),
        }
    }

    #[cfg(test)]
    pub(crate) fn new_with_range(range: Range) -> Encoder {
        Encoder {
            scratch: Scratch::new(),
            range,
        }
    }

    /// Encode a range. This is the fundamental unit of work for the arithmetic encoding.
    ///
    /// This function is designed to be called in a processing loop, though it does no looping or
    /// recursion on its own.
    ///
    /// For input, it takes a series of "state" values. These should be initialized to zero on the
    /// first call, and passed from this functions output on subsequent calls.
    ///
    /// This function is comlicated by the need to process an unknown number of mid zooms. A low
    /// zoom emits a 1, a high zoom emits a 0, but a mid-zoom could be either and won't be resolved
    /// until the next high/low zoom. In a 1TB file we might expect to have runs of mid-zooms up to
    /// maybe 20 (this assumes that the chance of a mid-zoom is ~1/4). Getting a run of 30 is
    /// exceedingly unlikely. But still this algorithm must account for the possiblity.
    ///
    /// To handle this corner case, this algorithm keeps track of at least 32 and up to 63 such
    /// unresolved mid zooms (total number depends on exactly where in mod 32 the start of the
    /// mid-zooms falls). After the storage for these zooms is exhausted, no more mid zooms are
    /// allowed, allowing the $high/$low window to shrink below the normal min of 2^30. As that
    /// window shrinks, the fidelity of the compression drops, eventually reaching 0 compression if
    /// the window gets to size 1. At that point, up to 32 bits of low/high zooms will be generated,
    /// allowing the mid-zooms to be resolved, and resetting the dangling mid-zoom counter to 0. In
    /// affect, this contingency will never get hit (outside of heavily tuned test code) and won't
    /// impact compression. Also, it will be evealuated as an extremely unlikely branch, allowing
    /// near zero performance loss as the CPUs branch predictors do their job.
    #[cfg_attr(target_family = "wasm", inline(always))]
    fn encode_range(&mut self) -> EncodeResult {
        self.scratch
            .apply_zoom(&self.range.zoom(self.scratch.max_mid_zooms()))
    }

    #[cfg_attr(target_family = "wasm", inline(always))]
    pub fn encode_bit(&mut self, bit: bool, p: u32) -> Result<EncodeResult, EncodeError> {
        if p != 0 {
            let mid = self.range.weighted_mid(p);
            if bit {
                self.range.high = mid;
            } else {
                self.range.low = mid;
            }
            return Result::Ok(self.encode_range());
        } else {
            if bit {
                return Err(EncodeError::BitSetWithProbabilityZero);
            }
            Result::Ok(EncodeResult {
                result: 0,
                result_count: 0,
            })
        }
    }

    #[cfg_attr(target_family = "wasm", inline(always))]
    pub fn encode_bit_ratio(
        &mut self,
        bit: bool,
        p_num: u32,
        p_den: u32,
    ) -> Result<EncodeResult, EncodeError> {
        if p_num > p_den {
            return Err(EncodeError::ProbabilityGreaterThanOne);
        }
        if p_num == 0 {
            if bit {
                return Err(EncodeError::BitSetWithProbabilityZero);
            }
            return Ok(EncodeResult {
                result: 0,
                result_count: 0,
            });
        }
        if p_num == p_den {
            if !bit {
                return Err(EncodeError::BitUnsetWithProbabilityOne);
            }
            return Ok(EncodeResult {
                result: 0,
                result_count: 0,
            });
        }
        let mid = self.range.weighted_mid_ratio(p_num, p_den);
        if bit {
            self.range.high = mid;
        } else {
            self.range.low = mid;
        }
        return Ok(self.encode_range());
    }

    #[cfg_attr(target_family = "wasm", inline(always))]
    pub fn encode_bit_f64(&mut self, bit: bool, p: f64) -> Result<EncodeResult, EncodeError> {
        if p > 1.0 {
            return Err(EncodeError::ProbabilityGreaterThanOne);
        }
        if p < 0.0 {
            return Err(EncodeError::ProbabilityLessThanZero);
        }
        if p == 0.0 {
            if bit {
                return Err(EncodeError::BitSetWithProbabilityZero);
            }
            return Ok(EncodeResult {
                result: 0,
                result_count: 0,
            });
        }
        if p == 1.0 {
            if !bit {
                return Err(EncodeError::BitUnsetWithProbabilityOne);
            }
            return Ok(EncodeResult {
                result: 0,
                result_count: 0,
            });
        }
        let mid = self.range.weighted_mid_f64(p);
        if bit {
            self.range.high = mid;
        } else {
            self.range.low = mid;
        }
        return Ok(self.encode_range());
    }
}

#[cfg(target_family = "wasm")]
#[cfg_attr(target_family = "wasm", wasm_bindgen)]
pub fn zoom(low: u32, high: u32) -> u64 {
    let mut range = Range { low, high };
    let zoom_result = range.zoom(63);
    (zoom_result.zooms as u64) << 32 | (zoom_result.outer_zooms as u64)
}

#[cfg(target_family = "wasm")]
#[cfg_attr(target_family = "wasm", wasm_bindgen)]
pub fn encode_bit(low: u32, high: u32, bit: bool, p: u32) {
    let mut encoder = Encoder::new();
    encoder.range.low = low;
    encoder.range.high = high;
    match encoder.encode_bit(bit, p) {
        Ok(EncodeResult {
            result,
            result_count,
        }) => bit_encoded(result, result_count),
        Err(error_code) => error_handler(error_code as u32, 0, 0),
    }
}

#[cfg(target_family = "wasm")]
#[cfg_attr(target_family = "wasm", wasm_bindgen)]
pub fn encode_bit_ratio(low: u32, high: u32, bit: bool, p_num: u32, p_den: u32) {
    let mut encoder = Encoder::new();
    encoder.range.low = low;
    encoder.range.high = high;
    match encoder.encode_bit_ratio(bit, p_num, p_den) {
        Ok(EncodeResult {
            result,
            result_count,
        }) => bit_encoded(result, result_count),
        Err(error_code) => error_handler(error_code as u32, 0, 0),
    }
}

#[cfg(target_family = "wasm")]
#[cfg_attr(target_family = "wasm", wasm_bindgen)]
pub fn encode_bit_f64(low: u32, high: u32, bit: bool, p: f64) {
    let mut encoder = Encoder::new();
    encoder.range.low = low;
    encoder.range.high = high;
    match encoder.encode_bit_f64(bit, p) {
        Ok(EncodeResult {
            result,
            result_count,
        }) => bit_encoded(result, result_count),
        Err(error_code) => error_handler(error_code as u32, 0, 0),
    }
}

#[cfg(test)]
mod tests {
    mod range {
        mod zoom {
            use super::super::super::*;

            fn validate_zoom(
                low: u32,
                high: u32,
                zooms: u32,
                outer_zooms: u32,
                emitted_bits: u32,
                new_low: u32,
                new_high: u32,
            ) {
                let mut range = Range { low, high };
                assert_eq!(
                    range.zoom(63),
                    ZoomResult {
                        zooms,
                        outer_zooms,
                        emitted_bits,
                    }
                );
                assert_eq!((range.low, range.high), (new_low, new_high));
            }

            #[test]
            fn no_zoom_low() {
                validate_zoom(0x3fffffff, 0x80000000, 0, 0, 0, 0x3fffffff, 0x80000000);
            }
            #[test]
            fn single_zoom_low() {
                validate_zoom(0x3fffffff, 0x7fffffff, 1, 1, 0, 0x7ffffffe, 0xffffffff);
            }
            #[test]
            fn single_zoom_mid_lower() {
                validate_zoom(0x40000000, 0x80000000, 1, 0, 0, 0x80000000, 1);
            }
            #[test]
            fn no_zoom_high() {
                validate_zoom(0x7fffffff, 0xc0000000, 0, 0, 0, 0x7fffffff, 0xc0000000);
            }
            #[test]
            fn single_zoom_high() {
                validate_zoom(0x80000000, 0xc0000000, 1, 1, 0x80000000, 0, 0x80000001);
            }
            #[test]
            fn single_zoom_mid_upper() {
                validate_zoom(0x7fffffff, 0xbfffffff, 1, 0, 0, 0xfffffffe, 0x7fffffff);
            }
            #[test]
            fn max_zooms_low() {
                validate_zoom(0, 1, 31, 31, 0, 0, 0xffffffff);
            }
            #[test]
            fn max_zooms_high() {
                validate_zoom(0xfffffffe, 0xffffffff, 31, 31, 0xfffffffe, 0, 0xffffffff);
            }
            #[test]
            fn max_zooms_mid() {
                validate_zoom(
                    0x7fffffff, 0x80000000, 31, 0, 0x7ffffffe, 0x80000000, 0x7fffffff,
                );
            }
            #[test]
            fn identical_zooms() {
                validate_zoom(0xdeadbeef, 0xdeadbeef, 32, 32, 0xdeadbeef, 0, 0xffffffff);
            }
            #[test]
            fn many_zooms_arbitrary() {
                validate_zoom(
                    0b10110101001010110101001010011110,
                    0b10110101001010110101001010100000,
                    30,
                    26,
                    0b10110101001010110101001010011100,
                    0b10000000000000000000000000000000,
                    0b00111111111111111111111111111111,
                );
            }
        }
    }
    mod encode_state {
        mod encode_range {
            use super::super::super::*;

            #[test]
            fn does_nothing_with_large_range() {
                let mut encoder = Encoder::new_with_range(Range {
                    low: 0,
                    high: 0xffffffff,
                });
                let EncodeResult {
                    result,
                    result_count,
                } = encoder.encode_range();
                assert_eq!(encoder.scratch.scratch, 0);
                assert_eq!(encoder.scratch.scratch_idx, 0);
                assert_eq!(encoder.scratch.dangling_idx, 0);
                assert_eq!(result, 0);
                assert_eq!(result_count, 0);
                assert_eq!(encoder.range.low, 0);
                assert_eq!(encoder.range.high, 0xffffffff);
            }
        }
    }
}
