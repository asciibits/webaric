#[derive(PartialEq, Debug)]
pub struct Range {
    pub low: u32,
    pub high: u32,
}

impl Range {
    #[cfg_attr(target_family = "wasm", inline(always))]
    pub fn new() -> Range {
        Range {
            low: 0,
            high: 0xffffffff,
        }
    }

    /// Calculate a weighted mid-point value in the range [low, high] proportional to p / 2^32.
    #[cfg_attr(target_family = "wasm", inline(always))]
    pub(crate) fn weighted_mid(&self, p: u32) -> u32 {
        ((((self.high.wrapping_sub(self.low)) as u64 + 1) * p as u64) >> 32) as u32 + self.low
    }

    /// Calculate a weighted mid-point value in the range [low, high] proportional to p_num /
    /// p_dden.
    ///
    /// Note: A p_den value of zero will trap due to division by zero. Use `weighted_mid` for a
    /// version that works on the full 2^32 range.
    #[cfg_attr(target_family = "wasm", inline(always))]
    pub(crate) fn weighted_mid_ratio(&self, p_num: u32, p_den: u32) -> u32 {
        ((((self.high.wrapping_sub(self.low)) as u64 + 1) * p_num as u64) / p_den as u64) as u32
            + self.low
    }

    /// Find the weighted midpoint for a given low/high region, and a given percentage.
    ///
    /// Note: This algorith only uses operations that are perfectly specified by the IEEE 754 spec,
    /// and so this function is consistent across all compliant WASM implementations. Assuming the
    /// f64 param was generated using *only* those instructions with strict rounding requirements,
    /// this function *should* be platform independent. That includes the operators: +, -, *, /, and
    /// sqrt. All other operations *will* have platform dependent rounding issues. This includes
    /// values generated from the suite of Javascript functions defined in Math. (Possibly with the
    /// exception of Math.sqrt; Through V15 of the ECMA-262 spec, Math.sqrt was allowed to be an
    /// "implementation-approximated" value:
    /// https://262.ecma-international.org/15.0/index.html?#sec-math.sqrt. Starting with V16 (2025),
    /// Math.sqrt is required to be IEEE754 compliant:
    /// https://262.ecma-international.org/16.0/index.html?#sec-math.sqrt ) Regardless, the f64.sqrt
    /// and f32.sqrt are both well defined, and thus consistent.
    #[cfg_attr(target_family = "wasm", inline(always))]
    pub(crate) fn weighted_mid_f64(&self, p: f64) -> u32 {
        self.weighted_mid((p * 4294967296.0) as u32)
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
    /// ($outer_zooms
    /// + 1) bits, we know that the $masked_xor will be zero (For the first $outer_zooms bits, the
    /// bits match so the $xor will be 0, and for the following bit $low will be 0). After that,
    /// every consecutive 1 bit is a valid mid-zoom.
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
    pub fn zoom(&mut self, max_mid_zooms: u32) -> ZoomResult {
        let xor = self.low ^ self.high;
        let outer_zooms = xor.leading_zeros();
        let mut zooms =
            outer_zooms + ((xor & self.low).wrapping_shl(outer_zooms + 1)).leading_ones();
        let emitted_bits: u32;
        if zooms == 32 {
            // very unlikely branch
            emitted_bits = self.low;
            self.low = 0;
            self.high = 0xffffffff;
        } else {
            if zooms > max_mid_zooms && outer_zooms == 0 {
                // very unlikely branch
                zooms = max_mid_zooms;
            }
            // expected branch
            emitted_bits = self.low & !(0xffffffff_u32 >> zooms);
            self.low <<= zooms;
            self.high = ((self.high.wrapping_add(1)) << zooms).wrapping_sub(1);
        }
        ZoomResult {
            zooms,
            outer_zooms,
            emitted_bits,
        }
    }
}

#[derive(PartialEq, Debug)]
pub struct Scratch {
    pub scratch: u64,
    pub scratch_idx: u32,
    pub dangling_idx: u32,
}

impl Scratch {
    #[cfg_attr(target_family = "wasm", inline(always))]
    pub fn new() -> Scratch {
        Scratch {
            scratch: 0,
            scratch_idx: 0,
            dangling_idx: 0,
        }
    }
    #[cfg_attr(target_family = "wasm", inline(always))]
    pub fn max_mid_zooms(&self) -> u32 {
        63 - self.scratch_idx
    }

    #[cfg_attr(target_family = "wasm", inline(always))]
    pub fn apply_zoom(&mut self, zoom_result: &ZoomResult) -> EncodeResult {
        if zoom_result.zooms != 0 {
            let mut result = self.scratch;
            let mut result_count: u32 = 0;

            self.scratch |= ((zoom_result.emitted_bits as u64) << 32) >> self.scratch_idx;
            if zoom_result.outer_zooms != 0 {
                if self.scratch_idx > self.dangling_idx {
                    // we have an outer zoom - resolve the dangling mids
                    self.scratch = self
                        .scratch
                        .wrapping_add(0x8000000000000000 >> self.scratch_idx);
                }
                self.dangling_idx = self.scratch_idx + zoom_result.outer_zooms;
                self.scratch_idx += zoom_result.zooms;

                result = self.scratch;
                result_count = self.dangling_idx >> 5;

                if self.scratch_idx >= 64 {
                    self.scratch = (self.scratch << 32)
                        | (zoom_result.emitted_bits << (self.scratch_idx - 64)) as u64;
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
                self.scratch_idx += zoom_result.zooms;
                if self.scratch_idx > 63 {
                    // mid-zooms overwrote scratch. This branch is absurdly unlikely. Clean up
                    // the various pieces that received the wrong values.
                    self.scratch_idx = 63;
                    self.scratch &= 0xfffffffe;
                }
            }

            EncodeResult {
                result,
                result_count,
            }
        } else {
            EncodeResult {
                result: 0,
                result_count: 0,
            }
        }
    }
}

#[derive(PartialEq, Debug)]
pub struct ZoomResult {
    pub zooms: u32,
    pub outer_zooms: u32,
    pub emitted_bits: u32,
}

#[derive(PartialEq, Debug)]
pub struct EncodeResult {
    pub result: u64,
    pub result_count: u32,
}
