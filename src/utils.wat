(module
  ;; DEBUG_START
  (func $ilog1 (export  "log1") (import "test" "log1") (param i32))
  (func $ilog2 (export  "log2") (import "test" "log2") (param i32 i32))
  (func $ilog3 (export  "log3") (import "test" "log3") (param i32 i32 i32))
  (func $ilog4 (export  "log4") (import "test" "log4") (param i32 i32 i32 i32))
  (func $ilog5 (export  "log5") (import "test" "log5") (param i32 i32 i32 i32 i32))
  (func $ilog6 (export  "log6") (import "test" "log6") (param i32 i32 i32 i32 i32 i32))
  (func $ilog64_1 (export  "log64_1") (import "test" "log64_1") (param i64))
  (func $ilog64_2 (export  "log64_2") (import "test" "log64_2") (param i64 i64))
  (func $ilog64_3 (export  "log64_3") (import "test" "log64_3") (param i64 i64 i64))
  (func $ilog64_4 (export  "log64_4") (import "test" "log64_4") (param i64 i64 i64 i64))
  (func $ilog64_5 (export  "log64_5") (import "test" "log64_5") (param i64 i64 i64 i64 i64))
  (func $ilog64_6 (export  "log64_6") (import "test" "log64_6") (param i64 i64 i64 i64 i64 i64))

  (func $random32 (import "test" "random32") (result i32))
  (func $nanonow (import "test" "nanonow") (result i64))

  (memory $benchmark_data 64)

  (func $benchmark_reverse32 (export "_benchmark_reverse32")
    (param $trials i32) (result i64)
    (local $i i32)
    (local $start i64)
    (local.set $i
      (i32.shl (i32.sub (local.get $trials) (i32.const 1)) (i32.const 2))
    )
    ;; load benchmark_data with random values
    (loop $load_data
      (i32.store $benchmark_data (local.get $i) (call $random32))
      (br_if $load_data (local.tee $i (i32.sub (local.get $i) (i32.const 4))))
    )

    (local.set $i
      (i32.shl (i32.sub (local.get $trials) (i32.const 1)) (i32.const 2))
    )
    (local.set $start (call $nanonow))
    (loop $reverse
      (i32.store $benchmark_data
        (local.get $i)
        (call $reverse32 (i32.load $benchmark_data (local.get $i)))
      )
      (br_if $reverse (local.tee $i (i32.sub (local.get $i) (i32.const 4))))
    )

    (i64.sub (call $nanonow) (local.get $start))
  )
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
  (func $not64 (export "_not64") (param i64) (result i64)
    (i64.xor (local.get 0) (i64.const -1))
  )

  (func $reverse_i8 (param i64) (result i64)
    ;; see https://graphics.stanford.edu/~seander/bithacks.html#ReverseByteWith64Bits
    ;;b = ((b * 0x80200802) & 0x0884422110) * 0x0101010101 >> 32;
    (i64.and
      (i64.shr_u
        (i64.mul
          (i64.and
            (i64.mul (local.get 0) (i64.const 0x80200802))
            (i64.const 0x0884422110)
          )
          (i64.const 0x0101010101)
        )
        (i64.const 32)
      )
      (i64.const 0xff)
    )
  )

  (func $reverse32 (export "_reverse32") (param i32) (result i32)
    ;; Shockingly, this is faster than the v128 version below
    (i32.shl
      (i32.wrap_i64
        (call $reverse_i8
          (i64.extend_i32_u (i32.and (local.get 0) (i32.const 0xff)))
        )
      )
      (i32.const 24)
    )
    (i32.shl
      (i32.wrap_i64
        (call $reverse_i8
          (i64.extend_i32_u
            (i32.and (i32.shr_u (local.get 0) (i32.const 8)) (i32.const 0xff))
          )
        )
      )
      (i32.const 16)
    )
    (i32.shl
      (i32.wrap_i64
        (call $reverse_i8
          (i64.extend_i32_u
            (i32.and (i32.shr_u (local.get 0) (i32.const 16)) (i32.const 0xff))
          )
        )
      )
      (i32.const 8)
    )
    (i32.wrap_i64
      (call $reverse_i8
        (i64.extend_i32_u
          (i32.and (i32.shr_u (local.get 0) (i32.const 24)) (i32.const 0xff))
        )
      )
    )
    i32.or
    i32.or
    i32.or
  )
  ;; (func $reverse32 (export "_reverse32") (param i32) (result i32)
  ;;   ;; apply the following technique in parallel:
  ;;   ;; https://graphics.stanford.edu/~seander/bithacks.html#ReverseByteWith32Bits
  ;;   (local $v v128)
  ;;   (local.set $v
  ;;     (i8x16.shuffle 0 9 10 11 1 13 14 15 2 9 10 11 3 13 14 15
  ;;       (i32x4.replace_lane 0 (v128.const i64x2 0 0) (local.get 0))
  ;;       (local.get $v)
  ;;     )
  ;;   )

  ;;   (i32x4.extract_lane 0
  ;;     (i8x16.shuffle 14 10 6 2 4 5 6 7 8 9 10 11 12 13 14 15
  ;;       (i32x4.mul
  ;;         (v128.or
  ;;           (v128.and
  ;;             (i32x4.mul (local.get $v) (i32x4.splat (i32.const 0x0802)))
  ;;             (i32x4.splat (i32.const 0x22110))
  ;;           )
  ;;           (v128.and
  ;;             (i32x4.mul (local.get $v) (i32x4.splat (i32.const 0x08020)))
  ;;             (i32x4.splat (i32.const 0x88440))
  ;;           )
  ;;         )
  ;;         (i32x4.splat (i32.const 0x10101))
  ;;       )
  ;;       (local.get $v)
  ;;     )
  ;;   )
  ;; )

  (func $reverse64 (export "_reverse64") (param i64) (result i64)
    (local $v1 v128)
    (local $v2 v128)

    (local.set $v1
      (i8x16.shuffle 0 9 10 11 1 13 14 15 2 9 10 11 3 13 14 15
      ;; (i8x16.swizzle
        (i64x2.replace_lane 0 (v128.const i64x2 0 0) (local.get 0))
        (local.get $v1)
        ;; (v128.const i8x16 0 9 10 11 1 13 14 15 2 9 10 11 3 13 14 15)
      )
    )
    (local.set $v2
      (i8x16.shuffle 4 9 10 11 5 13 14 15 6 9 10 11 7 13 14 15
      ;; (i8x16.swizzle
        (i64x2.replace_lane 0 (v128.const i64x2 0 0) (local.get 0))
        (local.get $v2)
        ;; (v128.const i8x16 4 9 10 11 5 13 14 15 6 9 10 11 7 13 14 15)
      )
    )

    (i64x2.extract_lane 0
      (i8x16.shuffle 30 26 22 18 14 10 6 2 8 9 10 11 12 13 14 15
        (i32x4.mul
          (v128.or
            (v128.and
              (i32x4.mul (local.get $v1) (i32x4.splat (i32.const 0x0802)))
              (i32x4.splat (i32.const 0x22110))
            )
            (v128.and
              (i32x4.mul (local.get $v1) (i32x4.splat (i32.const 0x08020)))
              (i32x4.splat (i32.const 0x88440))
            )
          )
          (i32x4.splat (i32.const 0x10101))
        )
        (i32x4.mul
          (v128.or
            (v128.and
              (i32x4.mul (local.get $v2) (i32x4.splat (i32.const 0x0802)))
              (i32x4.splat (i32.const 0x22110))
            )
            (v128.and
              (i32x4.mul (local.get $v2) (i32x4.splat (i32.const 0x08020)))
              (i32x4.splat (i32.const 0x88440))
            )
          )
          (i32x4.splat (i32.const 0x10101))
        )
      )
    )
  )

  (func $make32x4 (export "_make32x4") (param i32 i32 i32 i32) (result v128)
    (v128.const i64x2 0 0)
    (i32x4.replace_lane 0 (local.get 0))
    (i32x4.replace_lane 1 (local.get 1))
    (i32x4.replace_lane 2 (local.get 2))
    (i32x4.replace_lane 3 (local.get 3))
  )

  (func $make32x2 (export "_make32x2") (param i32 i32) (result v128)
    (v128.const i64x2 0 0)
    (i32x4.replace_lane 0 (local.get 0))
    (i32x4.replace_lane 1 (local.get 1))
  )

  (func $get32x4 (export "_get32x4") (param v128) (result i32 i32 i32 i32)
    (i32x4.extract_lane 0 (local.get 0))
    (i32x4.extract_lane 1 (local.get 0))
    (i32x4.extract_lane 2 (local.get 0))
    (i32x4.extract_lane 3 (local.get 0))
  )

  (func $get32x2 (export "_get32x2") (param v128) (result i32 i32)
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
  (func $ilog128 (export "_ilog128") (param i64) (param v128)
    (call $ilog64_3
      (local.get 0)
      (i64x2.extract_lane 0 (local.get 1))
      (i64x2.extract_lane 1 (local.get 1))
    )
  )
  (func $log128 (export "_log128") (param v128 i64) (result v128)
    (call $ilog128 (local.get 1) (local.get 0))
    local.get 0
  )
  (func $log64_1 (export "_log64_1") (param i64)
    (call $ilog64_1 (local.get 0))
  )
  (func $log64_2 (export "_log64_2") (param i64 i64) (result i64)
    (call $ilog64_2 (local.get 1) (local.get 0))
    local.get 0
  )
  (func $log64_3 (export "_log64_3") (param i64 i64 i64) (result i64 i64)
    (call $ilog64_3 (local.get 2) (local.get 0) (local.get 1))
    local.get 0
    local.get 1
  )
  (func $log64_4 (export "_log64_4") (param i64 i64 i64 i64) (result i64 i64 i64)
    (call $ilog64_4 (local.get 3) (local.get 0) (local.get 1) (local.get 2))
    local.get 0
    local.get 1
    local.get 2
  )
  ;; DEBUG_END
)
