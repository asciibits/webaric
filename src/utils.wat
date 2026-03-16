(module
  ;; DEBUG_START
  (func $ilog1 (import "test" "log1") (param i32))
  (func $ilog2 (import "test" "log2") (param i32 i32))
  (func $ilog3 (import "test" "log3") (param i32 i32 i32))
  (func $ilog4 (import "test" "log4") (param i32 i32 i32 i32))
  (func $ilog5 (import "test" "log5") (param i32 i32 i32 i32 i32))
  (func $ilog6 (import "test" "log6") (param i32 i32 i32 i32 i32 i32))
  (func $ilog64_1 (import "test" "log64_1") (param i32))
  (func $ilog64_2 (import "test" "log64_2") (param i32 i32))
  (func $ilog64_3 (import "test" "log64_3") (param i32 i32 i32))
  (func $ilog64_4 (import "test" "log64_4") (param i32 i32 i32 i32))
  (func $ilog64_5 (import "test" "log64_5") (param i32 i32 i32 i32 i32))
  (func $ilog64_6 (import "test" "log64_6") (param i32 i32 i32 i32 i32 i32))
  ;; DEBUG_END

  (func $min32 (export "_min32") (param i32 i32) (result i32)
    (select
      (local.get 0)
      (local.get 1)
      (i32.le_u (local.get 0) (local.get 1))
    )
  )
  (func $max32 (export "_max32") (param i32 i32) (result i32)
    (select
      (local.get 0)
      (local.get 1)
      (i32.ge_u (local.get 0) (local.get 1))
    )
  )
  (func $not32 (export "_not32") (param i32) (result i32)
    (i32.xor (local.get 0) (i32.const -1))
  )

  (func $make4x32 (export "_make4x32") (param i32 i32 i32 i32) (result v128)
    (v128.const i64x2 0 0)
    (i32x4.replace_lane 0 (local.get 0))
    (i32x4.replace_lane 1 (local.get 1))
    (i32x4.replace_lane 2 (local.get 2))
    (i32x4.replace_lane 3 (local.get 3))
  )

  (func $make2x32 (export "_make2x32") (param i32 i32) (result v128)
    (v128.const i64x2 0 0)
    (i32x4.replace_lane 0 (local.get 0))
    (i32x4.replace_lane 1 (local.get 1))
  )

  (func $get4x32 (export "_get4x32") (param v128) (result i32 i32 i32 i32)
    (i32x4.extract_lane 0 (local.get 0))
    (i32x4.extract_lane 1 (local.get 0))
    (i32x4.extract_lane 2 (local.get 0))
    (i32x4.extract_lane 3 (local.get 0))
  )

  (func $get2x32 (export "_get2x32") (param v128) (result i32 i32)
    (i32x4.extract_lane 0 (local.get 0))
    (i32x4.extract_lane 1 (local.get 0))
  )

  ;; Calculate a weighted mid-point value in the range [low, high] proportional
  ;; to p_n / p_d.
  ;;
  ;; Note: A $p_d value of zero will trap due to division by zero. Use $mid_i32
  ;; for a version that works on the full 2^32 range.
  (func $mid_ratio (export "_mid_ratio")
    ;; The low value. 0 <= $low < 2^32-1
    (param $low i32)
    ;; The high value. $low < $high < 2^32
    (param $high i32)
    ;; numerator of the probability. p = p_n / p_d
    ;; 0 <= p_n <= p_d
    (param $p_n i32)
    ;; denominator of the probability. p = p_n / p_d
    ;; 0 < p_d < 2^32
    (param $p_d i32)

    ;; the weighted mid-point. $low <= result <= $high, except that in the case
    ;; where $high is 0 (representing 2^32), and $p_n == $p_d, then the result
    ;; will be the i64 value 2^32, not the truncated i32 value 0.
    (result i64)

    ;; mid = start + offset
    ;; 0 <= mid <= 2^32
    (i64.add
      ;; offset = range * p_n / p_d
      ;; 0 <= offset <= range
      (i64.div_u
        (i64.mul
          ;; range = high - low
          ;; 0 < range < 2^32
          (i64.extend_i32_u (i32.sub (local.get $high) (local.get $low)))
          (i64.extend_i32_u (local.get $p_n))
        )
        (i64.extend_i32_u (local.get $p_d))
      )
      ;; start = low + (p_n == 0 ? 0 : 1)
      (i64.extend_i32_u
        (i32.add
          (local.get $low)
          (i32.ne (local.get $p_n) (i32.const 0))
        )
      )
    )
  )

  ;; Calculate a weighted mid-point value in the range [low, high] proportional
  ;; to p / 2^32.
  (func $mid_i32 (export "_mid_i32")
    ;; The low value. 0 <= $low < 2^32-1
    (param $low i32)
    ;; The high value. $low < $high < 2^32
    (param $high i32)
    ;; probability of a '1' bit: p/2^32
    ;; 0 <= p <= 2^32
    (param $p i64)

    ;; the weighted mid-point. $low <= result <= $high, except that in the case
    ;; where $high is 0 (representing 2^32), and $p == 2^32 then the result
    ;; will be the i64 value 2^32, not the truncated i32 value 0.
    (result i64)

    ;; mid = start + offset
    ;; 0 <= mid <= 2^32
    (i64.add
      ;; offset = range * p_n / p_d
      ;; 0 <= offset <= range
      (i64.shr_u
        (i64.mul
          ;; range = high - low - 1
          ;; 0 < range < 2^32
          (i64.extend_i32_u (i32.sub (local.get $high) (local.get $low)))
          (local.get $p)
        )
        (i64.const 32)
      )
      ;; start = low + (p == 0 ? 0 : 1)
      (i64.extend_i32_u
        (i32.add
          (local.get $low)
          (i64.ne (local.get $p) (i64.const 0))
        )
      )
    )
  )

  ;; Find the weighted midpoint for a given low/high region, and a given
  ;; percentage.
  ;;
  ;; Note: This algorith only uses operations that are perfectly specified by
  ;; the IEEE 754 spec, and so this function is consistent across all compliant
  ;; WASM implementations. Assuming the f64 param was generated using *only*
  ;; those instructions with strict rounding requirements, this function
  ;; *should* be platform independent. That includes the operators:
  ;; +, -, *, /, and sqrt. All other operations *will* have platform dependent
  ;; rounding issues. This includes values generated from the suite of
  ;; Javascript functions defined in Math. (Possibly with the exception of
  ;; Math.sqrt; Through V15 of the ECMA-262 spec, Math.sqrt was allowed to be
  ;; an "implementation-approximated" value:
  ;; https://262.ecma-international.org/15.0/index.html?#sec-math.sqrt.
  ;; Starting with V16 (2025), Math.sqrt is required to be IEEE754 compliant:
  ;; https://262.ecma-international.org/16.0/index.html?#sec-math.sqrt )
  ;; Regardless, the f64.sqrt and f32.sqrt are both well defined, and thus
  ;; consistent.
  (func $mid_f64 (export "_mid_f64")
    ;; The low value. 0 <= $low < 2^32-1
    (param $low i32)
    ;; The high value. $low < $high < 2^32
    (param $high i32)
    ;; Percentage of range. 0 <= $p <= 1.0
    (param $p f64)

    ;; the weighted mid-point. $low <= result <= $high, except that in the case
    ;; where $high is 0 (representing 2^32), and $p == 0 and $bit != 0, then
    ;; the result will be the i64 value 2^32, not the truncated i32 value 0.
    (result i64)

    (call $mid_i32
      (local.get $low)
      (local.get $high)
      (i64.trunc_sat_f64_u (f64.mul (local.get $p) (f64.const 0x100000000)))
    )
  )


  ;; DEBUG_START
  (func $log1 (export "_log1") (param i32)
    (call $ilog1 (local.get 0))
  )
  (func $log2 (export "_log2") (param i32 i32) (result i32)
    (call $ilog2 (local.get 1) (local.get 0))
    local.get 0
  )
  (func $log3 (export "_log3") (param i32 i32 i32) (result i32 i32)
    (call $ilog3 (local.get 2) (local.get 0) (local.get 1))
    local.get 0
    local.get 1
  )
  (func $log4 (export "_log4") (param i32 i32 i32 i32) (result i32 i32 i32)
    (call $ilog4 (local.get 3) (local.get 0) (local.get 1) (local.get 2))
    local.get 0
    local.get 1
    local.get 2
  )
  ;; DEBUG_END
)
