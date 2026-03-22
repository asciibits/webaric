use crate::utils::Range;

#[cfg(target_family = "wasm")]
use wasm_bindgen::prelude::wasm_bindgen;

#[cfg(target_family = "wasm")]
#[cfg_attr(target_family = "wasm", wasm_bindgen)]
extern "C" {
    // encode bit result callback
    fn bit_encoded(result: u64, result_count: u32);

    // javascript logging functions
    #[cfg(feature = "js_debug")]
    fn log32_1(a: u32);
    #[cfg(feature = "js_debug")]
    fn log32_2(a: u32, b: u32);
    #[cfg(feature = "js_debug")]
    fn log32_3(a: u32, b: u32, c: u32);
}

#[derive(PartialEq, Debug)]
struct ZoomResult {
    zooms: u32,
    outer_zooms: u32,
    emitted_bits: u64,
}

pub struct Encoder {
    scratch: u64,
    scratch_idx: u32,
    dangling_idx: u32,
    range: crate::utils::Range,
}

pub struct EncodeResult {
    pub result: u64,
    pub result_count: u32,
}

impl Encoder {
    #[cfg_attr(target_family = "wasm", inline(always))]
    pub fn new() -> Encoder {
        Encoder {
            scratch: 0,
            scratch_idx: 0,
            dangling_idx: 0,
            range: Range {
                low: 0,
                high: 0xffffffff,
            },
        }
    }

    #[cfg(test)]
    pub(crate) fn new_with_range(range: Range) -> Encoder {
        Encoder {
            scratch: 0,
            scratch_idx: 0,
            dangling_idx: 0,
            range,
        }
    }

    /// Calculate the number of times we can "zoom" into a windowed region.
    ///
    /// The range considered is all possible i32 values for both $low and $high. 0 <= $low <= $high
    /// < 2^32
    ///
    /// Every "zoom" represents doubling the gap between $high and $low. We consider only three
    /// potential zooms:
    ///
    /// "zoom low": both $low and $high are in the bottom half of i32 values (i.e. their leading bit
    /// is a 0). In this case, both values are doubled, and we record a "zoom_low". Note: because
    /// the values are alread <= 2^31, doubling their values keeps them within the i32 range.
    ///
    /// "zoom high": both $low and $high are in the top half of i32 values (i.e. their leading bit
    /// is a 1). In this case, we first subtract 2^31, then double, and we record a "zoom_high". By
    /// subtracting 2^31 first, we keep the resulting values in the i32 range.
    ///
    /// "zoom mid": both $low and $high are between the "quarter" and "three quarter" i32 values,
    /// where "quarter" is (2^32 / 4) or 2^30, and "three quarter" is (2^32 * 3 / 4) or (2^31 +
    /// 2^30). In this case, we first subtract 2^30, then double, and we record a "zoom_mid". By
    /// subtracting 2^30, we keep the resulting values in the i32 range.
    ///
    /// This function needs to communicate the ordered list of available zooms for the provided
    /// range. So, something like: ["high", "low", "low", "mid", ...]
    ///
    /// One simplification is recognizing that a mid zoom can't be followed by either a low or a
    /// high zoom. This is because a mid zoom only happens when $high/$low straddle 2^31 - one is
    /// above, the other below. (If both were below, we would instead opt for a low zoom, and if
    /// both were above, a high zoom). After a mid-zoom, $high will still be above 2^31 - in fact it
    /// will be twice as far above 2^31 as it was before the zoom. Similarly, $low will be twice as
    /// far below 2^31 as it was previously. With the boundaries continuing to straddle the
    /// mid-point, only another mid zoom will be possible.
    ///
    /// Since all mid-zooms (if there are any) occur after all high/low zooms, we can instead return
    /// two values: the list of high/low zooms, and a single mid_zooms count.
    ///
    /// Another simplification is that the initial set of high/low zooms will look very similar to
    /// the bit pattern of $low and $high. We only zoom high if both have a leading 1 bit. And we
    /// only zoom low if both have a leading 0 bit. So, we could just return the leading bit
    /// pattern; Or, even easier, just the number of available high/low zooms and let the caller
    /// pull the bit pattern out of $low or $high.
    ///
    /// So, this function can return two i32 values: "outer_zooms" (i.e. the number of high/low
    /// zooms), and "mid_zooms".
    ///
    /// Note: the max number of zooms is 32:
    ///
    ///   0 <= ($outer_zooms + $mid_zooms) <= 32
    ///
    /// Put another way, we can only double the minimum gap (1) 32 times before we hit the largest
    /// allowed window.
    ///
    /// It's also worth noting that a mid-zoom can't be the 32nd zoom. There is no way for a single
    /// remaining bit, after 31 previous zooms, to have the necessary condition of $low>=2^30 and
    /// $high<(2^31+2^30). So, the result can be further restricted to:
    ///
    /// if $mid_zooms > 0: 0 <= ($outer_zooms + $mid_zooms) <= 31
    ///
    /// Now for the optimized algorithm:
    ///
    /// First, note that a "zoom high" emits a '1', and undergoes a "(x-2^31)*2" The bit-pattern
    /// starts as: 0b1xx..xxx. The high bit is a '1' since it is
    /// >= 2^31. Subtracting 2^31 effectively clears that high bit, and the "*2" shifts the
    /// remainder to the left leaving: 0bxx..xxx0. Which can be viewed as "left shift, emit the bit
    /// falling off the left"
    ///
    /// Zoom lows are similar, except the high bit is a 0: 0b0yy..yyy. It is similarly shifted, this
    /// time emiting a '0', leaving: 0byy...yyy0. Again, it is "left shift, emit the bit falling off
    /// the left"
    ///
    /// And lastly, zoom mids work on values whose high bits are either 01 or 10 (Given the
    /// condition: 2^30 <= x < (2^31+2^30)) The algorithm "(x-2^30)*2" first subtracts that 2^30.
    /// Which changes the high bits as: 01 -> 00, 10 -> 01. I.e. the high bit becomes '0', and the
    /// 2nd high bit is flipped. Then it is bit shifted as above.
    ///
    /// Note that a high zoom is only possible when both $low and $high values have a high bit of 1.
    /// Similarly, a low zoom only happens when both have a high bit of 0. To find the set of
    /// initial high/low zooms, we just see how many high order bits both $high and $low have in
    /// common. Those become the "outer zooms".
    ///
    /// After that initial set of matching high order bits, the next bit of $low and $high will
    /// necessarily be different: $low will have a 0, $high a 1. A "mid zoom" is possible if the
    /// following bit of $high is a 0 (yielding 10), and the following bit of $low is a 1 (yielding
    /// 01). Additional mid-zooms are possible so long as $high continues to have 0 bits, and $low
    /// continues to have 1 bits.
    ///
    /// Consider the example:
    ///
    /// high = 0b10100100.. low  = 0b10011001..
    ///
    /// xor  = high ^ low = 0b00111101..
    ///
    /// The two leading zeros of that $xor represent the "outer zooms" - that is, we can zoom twice
    /// (in this case, once high, then once low).
    ///
    /// outer_zooms = clz(xor)  // = 2 in this example
    ///
    /// After the zeros the $xor will have a 1 bit where $low is necessarily a 0 and $high is a 1.
    /// After that, we want to know just how many cases exist where $low has a 1 while $high has a
    /// 0.
    ///
    /// masked_xor = low & xor = 0b00011001..
    ///
    /// This represents a bit pattern where $low has a 1 AND $high has a 0. For the first
    /// ($outer_zooms + 1) bits, we know that the $masked_xor will be zero (For the first
    /// $outer_zooms bits, the bits match so the $xor will be 0, and for the following bit $low will
    /// be 0). After that, every consecutive 1 bit is a valid mid-zoom.
    ///
    /// shifted_masked_xor = masked_xor << (outer_zooms + 1) = 0b11001..000
    ///
    /// Now with the 1 bits representing the mid-zooms at the left, we can invert the pattern and
    /// count the leading zeros:
    ///
    /// mid_zooms = clz(~shifted_masked_xor)  // = 2 in this example
    ///
    /// To summarize:
    ///
    /// xor = low ^ high outer_zooms = clz(xor) mid_zooms = clz(~((xor & low) << (outer_zooms + 1)))
    ///
    /// That's 7 total operations with no branching for an algorithm that could span a page with
    /// loops and branching if implemented in the naive way. Pretty sweet!
    ///
    /// Following any mid zooms, if we just shift without fixing the leading bits, we end up with:
    ///
    /// 0 <= $high < 2^31 <= $low < 2^32
    ///
    /// Interestingly, in this case, the above logic holds. We will always get a 0 for $outer_zooms,
    /// and the correct # for any viable mid zooms.
    #[cfg_attr(target_family = "wasm", inline(always))]
    fn zoom(range: &mut Range) -> ZoomResult {
        let xor = range.low ^ range.high;
        let outer_zooms = xor.leading_zeros();
        let zooms = outer_zooms + ((xor & range.low).wrapping_shl(outer_zooms + 1)).leading_ones();
        let emitted_bits: u32;
        if zooms == 32 {
            // very unlikely branch
            emitted_bits = range.low;
            range.low = 0;
            range.high = 0xffffffff;
        } else {
            // expected branch
            emitted_bits = range.low & !(0xffffffff_u32 >> zooms);
            range.low <<= zooms;
            range.high = ((range.high.wrapping_add(1)) << zooms).wrapping_sub(1);
        }
        ZoomResult {
            zooms,
            outer_zooms,
            emitted_bits: (emitted_bits as u64) << 32,
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
        let ZoomResult {
            zooms,
            outer_zooms,
            emitted_bits,
        } = Encoder::zoom(&mut self.range);

        let mut result_count = 0;
        let mut result: u64 = 0;

        if zooms != 0 {
            self.scratch |= emitted_bits >> self.scratch_idx;
            if outer_zooms != 0 {
                if self.scratch_idx > self.dangling_idx {
                    // we have an outer zoom - resolve the dangling mids
                    self.scratch = self
                        .scratch
                        .wrapping_add(0x8000000000000000 >> self.scratch_idx);
                }
                self.dangling_idx = self.scratch_idx + outer_zooms;
                self.scratch_idx += zooms;

                result = self.scratch;
                result_count = self.dangling_idx >> 5;

                if self.scratch_idx >= 64 {
                    self.scratch =
                        (self.scratch << 32) | ((emitted_bits << (self.scratch_idx - 64)) >> 32);
                    self.scratch_idx -= 32;
                    self.dangling_idx -= 32;
                }
                if self.dangling_idx >= 32 {
                    self.scratch <<= 32;
                    self.scratch_idx -= 32;
                    self.dangling_idx -= 32;
                }
            } else {
                // only mid-zooms
                self.scratch_idx += zooms;
                if self.scratch_idx > 63 {
                    // mid-zooms overwrote scratch. This branch is absurdly unlikely. Clean up
                    // the various pieces that received the wrong values.
                    let offset = self.scratch_idx - 63;
                    // we need to clean up low and high by replacing some of those emitted bits
                    let emitted_bits = ((emitted_bits << (zooms - offset)) >> 32) as u32;
                    self.range.low = (self.range.low >> offset) | emitted_bits;
                    self.range.high = (self.range.high >> offset) | emitted_bits;
                    if self.scratch_idx - zooms > self.dangling_idx {
                        // we were already in a mid-zoom; fix up high's bit pattern
                        self.range.high = self.range.high.wrapping_add(0x80000000 >> (offset - 1));
                    }

                    self.scratch_idx = 63;
                    self.scratch &= 0xfffffffe;
                }
            }
        }

        EncodeResult {
            result,
            result_count,
        }
    }

    #[cfg_attr(target_family = "wasm", inline(always))]
    pub fn encode_bit(&mut self, bit: bool, p: u32) -> EncodeResult {
        if p != 0 {
            let mid = self.range.weighted_mid(p);
            if bit {
                self.range.high = mid;
            } else {
                self.range.low = mid;
            }
            return self.encode_range();
        } else {
            // if bit {
            //     panic!("Bit set with zero probability")
            // }
            EncodeResult {
                result: 0,
                result_count: 0,
            }
        }
    }

    #[cfg_attr(target_family = "wasm", inline(always))]
    pub fn encode_bit_ratio(&mut self, bit: bool, p_num: u32, p_den: u32) -> EncodeResult {
        // if p_num > p_den {
        //     panic!("Probability greater than one")
        // }
        if p_num == 0 {
            // if bit {
            //     panic!("Bit set with zero probability")
            // }
            return EncodeResult {
                result: 0,
                result_count: 0,
            };
        }
        if p_num >= p_den {
            // if !bit {
            //     panic!("Bit unset with one probability")
            // }
            return EncodeResult {
                result: 0,
                result_count: 0,
            };
        }
        let mid = self.range.weighted_mid_ratio(p_num, p_den);
        if bit {
            self.range.high = mid;
        } else {
            self.range.low = mid;
        }
        return self.encode_range();
    }

    #[cfg_attr(target_family = "wasm", inline(always))]
    pub fn encode_bit_f64(&mut self, bit: bool, p: f64) -> EncodeResult {
        // if p > 1.0 {
        //     panic!("Probability greater than one")
        // }
        // if p < 0.0 {
        //     panic!("Probability less than zero")
        // }
        if p <= 0.0 {
            // if bit {
            //     panic!("Bit set with zero probability")
            // }
            return EncodeResult {
                result: 0,
                result_count: 0,
            };
        }
        if p >= 1.0 {
            // if !bit {
            //     panic!("Bit unset with one probability")
            // }
            return EncodeResult {
                result: 0,
                result_count: 0,
            };
        }
        let mid = self.range.weighted_mid_f64(p);
        if bit {
            self.range.high = mid;
        } else {
            self.range.low = mid;
        }
        return self.encode_range();
    }
}

#[cfg(target_family = "wasm")]
#[cfg_attr(target_family = "wasm", wasm_bindgen)]
pub fn zoom(low: u32, high: u32) -> u64 {
    let mut range = Range { low, high };
    let zoom_result = Encoder::zoom(&mut range);
    (zoom_result.zooms as u64) << 32 | (zoom_result.outer_zooms as u64)
}

#[cfg(target_family = "wasm")]
#[cfg_attr(target_family = "wasm", wasm_bindgen)]
pub fn encode_bit(low: u32, high: u32, bit: bool, p: u32) {
    let mut encoder = Encoder::new();
    encoder.range.low = low;
    encoder.range.high = high;
    let EncodeResult {
        result,
        result_count,
    } = encoder.encode_bit(bit, p);
    bit_encoded(result, result_count);
}

#[cfg(target_family = "wasm")]
#[cfg_attr(target_family = "wasm", wasm_bindgen)]
pub fn encode_bit_ratio(low: u32, high: u32, bit: bool, p_num: u32, p_den: u32) {
    let mut encoder = Encoder::new();
    encoder.range.low = low;
    encoder.range.high = high;
    let EncodeResult {
        result,
        result_count,
    } = encoder.encode_bit_ratio(bit, p_num, p_den);
    bit_encoded(result, result_count);
}

#[cfg(target_family = "wasm")]
#[cfg_attr(target_family = "wasm", wasm_bindgen)]
pub fn encode_bit_f64(low: u32, high: u32, bit: bool, p: f64) {
    let mut encoder = Encoder::new();
    encoder.range.low = low;
    encoder.range.high = high;
    let EncodeResult {
        result,
        result_count,
    } = encoder.encode_bit_f64(bit, p);
    bit_encoded(result, result_count);
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
                    Encoder::zoom(&mut range),
                    ZoomResult {
                        zooms,
                        outer_zooms,
                        emitted_bits: (emitted_bits as u64) << 32,
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
                assert_eq!(encoder.scratch, 0);
                assert_eq!(encoder.scratch_idx, 0);
                assert_eq!(encoder.dangling_idx, 0);
                assert_eq!(result, 0);
                assert_eq!(result_count, 0);
                assert_eq!(encoder.range.low, 0);
                assert_eq!(encoder.range.high, 0xffffffff);
            }
        }
    }
}
