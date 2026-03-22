pub struct Range {
    pub low: u32,
    pub high: u32,
}

impl Range {
    /// Calculate a weighted mid-point value in the range [low, high] proportional to p / 2^32.
    #[inline(always)]
    pub(crate) fn weighted_mid(&self, p: u32) -> u32 {
        (((self.high.wrapping_sub(self.low).wrapping_add(1)) as u64 * p as u64) >> 32) as u32
            + self.low
    }

    /// Calculate a weighted mid-point value in the range [low, high] proportional to p_num /
    /// p_dden.
    ///
    /// Note: A p_den value of zero will trap due to division by zero. Use `weighted_mid` for a
    /// version that works on the full 2^32 range.
    #[inline(always)]
    pub(crate) fn weighted_mid_ratio(&self, p_num: u32, p_den: u32) -> u32 {
        (((self.high.wrapping_sub(self.low).wrapping_add(1)) as u64 * p_num as u64) / p_den as u64)
            as u32
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
    #[inline(always)]
    pub(crate) fn weighted_mid_f64(&self, p: f64) -> u32 {
        self.weighted_mid((p * 4294967296.0) as u32)
    }
}
