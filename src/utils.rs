pub(crate) struct Range {
    pub(crate) low: u32,
    pub(crate) high: u32,
}

/// Calculate a weighted mid-point value in the range [low, high] proportional to p / 2^32.
pub(crate) fn weighted_mid(range: &Range, p: u32) -> u32 {
    (((range.high.wrapping_sub(range.low)) as u64 * p as u64) >> 32) as u32
        + range.low
        + if p == 0 { 0 } else { 1 }
}

/// Calculate a weighted mid-point value in the range [low, high] proportional to p_num / p_dden.
///
/// Note: A p_den value of zero will trap due to division by zero. Use `weighted_mid` for a version
/// that works on the full 2^32 range.
pub(crate) fn weighted_mid_ratio(range: &Range, p_num: u32, p_den: u32) -> u32 {
    (((range.high.wrapping_sub(range.low)) as u64 * p_num as u64) / p_den as u64) as u32
        + range.low
        + if p_num == 0 { 0 } else { 1 }
}

/// Find the weighted midpoint for a given low/high region, and a given percentage.
///
/// Note: This algorith only uses operations that are perfectly specified by the IEEE 754 spec, and
/// so this function is consistent across all compliant WASM implementations. Assuming the f64 param
/// was generated using *only* those instructions with strict rounding requirements, this function
/// *should* be platform independent. That includes the operators: +, -, *, /, and sqrt. All other
/// operations *will* have platform dependent rounding issues. This includes values generated from
/// the suite of Javascript functions defined in Math. (Possibly with the exception of Math.sqrt;
/// Through V15 of the ECMA-262 spec, Math.sqrt was allowed to be an "implementation-approximated"
/// value: https://262.ecma-international.org/15.0/index.html?#sec-math.sqrt. Starting with V16
/// (2025), Math.sqrt is required to be IEEE754 compliant:
/// https://262.ecma-international.org/16.0/index.html?#sec-math.sqrt ) Regardless, the f64.sqrt and
/// f32.sqrt are both well defined, and thus consistent.
pub(crate) fn weighted_mid_f64(range: &Range, p: f64) -> u32 {
    weighted_mid(range, (p * 4294967296.0) as u32)
}
