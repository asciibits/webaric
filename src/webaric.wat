(module
  ;; DEBUG_START
  (func $log1 (import "test" "log1") (param i32))
  (func $log2 (import "test" "log2") (param i32 i32))
  (func $log3 (import "test" "log3") (param i32 i32 i32))
  (func $log4 (import "test" "log4") (param i32 i32 i32 i32))
  (func $log5 (import "test" "log5") (param i32 i32 i32 i32 i32))
  (func $log6 (import "test" "log6") (param i32 i32 i32 i32 i32 i32))
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
  (func $not32 (param i32) (result i32)
    (i32.xor (local.get 0) (i32.const -1))
  )

  (func $make4x32 (param i32 i32 i32 i32) (result v128)
    (v128.const i64x2 0 0)
    (i32x4.replace_lane 0 (local.get 0))
    (i32x4.replace_lane 1 (local.get 1))
    (i32x4.replace_lane 2 (local.get 2))
    (i32x4.replace_lane 3 (local.get 3))
  )

  (func $make2x32 (param i32 i32) (result v128)
    (v128.const i64x2 0 0)
    (i32x4.replace_lane 0 (local.get 0))
    (i32x4.replace_lane 1 (local.get 1))
  )

  (func $get4x32 (param v128) (result i32 i32 i32 i32)
    (i32x4.extract_lane 0 (local.get 0))
    (i32x4.extract_lane 1 (local.get 0))
    (i32x4.extract_lane 2 (local.get 0))
    (i32x4.extract_lane 3 (local.get 0))
  )

  (func $get2x32 (param v128) (result i32 i32)
    (i32x4.extract_lane 0 (local.get 0))
    (i32x4.extract_lane 1 (local.get 0))
  )

  ;; apply the appropriate zoom for the (up to) 4 values in $v
  (func $apply_zoom
    (param $v v128)
    (param $known_bits i32)
    (param $trailing_mids i32)
    (result v128)

    (v128.xor
      (i32x4.shl
        (local.get $v)
        (i32.add (local.get $known_bits) (local.get $trailing_mids))
      )
      (i32x4.splat
        (i32.shl
          (i32.gt_u (local.get $trailing_mids) (i32.const 0))
          (i32.const 31)
        )
      )
    )
  )

  ;; Calculate a weighted mid-point value in the range [low, high] proportional
  ;; to p_n / p_d.
  ;;
  ;; Note: A $p_d value of zero will trap due to division by zero. Use $mid_i32
  ;; for a version that works on the full 2^32 range.
  (func $mid_ratio (export "_mid_ratio")
    ;; The low value. 0 <= $low < 2^32-1
    (param $low i32)
    ;; The high value. $low < $high-1 < 2^32
    ;; Note: A 0 indicates 2^32.
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
          ;; range = high - low - 1
          ;; 0 < range < 2^32
          (i64.extend_i32_u
            (i32.sub
              (i32.sub (local.get $high) (local.get $low))
              (i32.const 1)
            )
          )
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
    ;; The high value. $low < $high-1 < 2^32
    ;; Note: A 0 indicates 2^32.
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
          (i64.extend_i32_u
            (i32.sub
              (i32.sub (local.get $high) (local.get $low))
              (i32.const 1)
            )
          )
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
    ;; The high value. $low < $high-1 < 2^32
    ;; Note: A 0 indicates 2^32.
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


  ;; Calculate the number of times we can "zoom" into a windowed region while
  ;; keeping the boundaries within convenient ranges.
  ;;
  ;; The range considered is all possible i32 values for both $low and $high.
  ;; 0 <= $low < $high <= 2^32. Note that when $high is 0, that actually
  ;; represents the truncated value 2^32.
  ;;
  ;; Every "zoom" represents the gap between $high and $low doubling. We
  ;; consider only three potential zooms:
  ;;
  ;; "zoom low": both $low and ($high-1) are in the bottom half of i32 values
  ;; (i.e. their leading bit is a 0). In this case, both values are doubled,
  ;; and we record a "zoom_low". Note: because the values are alread <= 2^31,
  ;; doubling their values keeps them within the i32 range.
  ;;  
  ;; "zoom high": both $low and ($high-1) are in the top half of i32 values
  ;; (i.e. their leading bit is a 1). In this case, we first subtract 2^31,
  ;; then double, and we record a "zoom_high". By subtracting 2^31 first, we
  ;; keep the resulting values in the i32 range.
  ;;
  ;; "zoom mid": both $low and ($high-1) are between the "quarter" and "three
  ;; quarter" i32 values, where "quarter" is (2^32 / 4) or 2^30, and
  ;; "three quarter" is (2^32 * 3 / 4) or (2^31 + 2^30). In this case, we first
  ;; subtract 2^30, then double, and we record a "zoom_mid". By subtracting
  ;; 2^30, we keep the resulting values in the i32 range.
  ;;
  ;; This function needs to communicate the ordered list of available zooms for
  ;; the provided range. So, something like: ["high", "low", "low", "mid", ...]
  ;;
  ;; One simplification is recognizing that a mid zoom can't be followed by
  ;; either a low or a high zoom. This is because a mid zoom only happens when
  ;; $high/$low straddle 2^31 - one is above, the other below. (If both were
  ;; below, we would instead opt for a low zoom, and if both were above, a high
  ;; zoom). After a mid-zoom, $high will still be above 2^31 - in fact it will
  ;; be twice as far above 2^31 as it was before the zoom. Similarly, $low will
  ;; be twice as far below 2^31 as it was previously. With the boundaries
  ;; continuing to straddle the mid-point, only another mid zoom will be
  ;; possible.
  ;;
  ;; Since all mid-zooms (if there are any) occur after all high/low zooms, we
  ;; can instead return two values: the list of high/low zooms, and a single
  ;; mid_zoom_count.
  ;;
  ;; Another simplification is that the initial set of high/low zooms will
  ;; look very similar to the bit pattern of $low and ($high-1). We only zoom
  ;; high if both have a leading 1 bit. And we only zoom low if both have a
  ;; leading 0 bit. So, we could just return the leading bit pattern of $low;
  ;; Or, even easier, just the number of available high/low zooms and let the
  ;; caller pull the bit pattern out of low.
  ;;
  ;; So, this function returns two i32 values: "outer_zooms" (i.e. the number
  ;; of high/low zooms), and "mid_zooms".
  ;;
  ;; Note: the max number of zooms is 32:
  ;;
  ;;   0 <= ($outer_zooms + $mid_zooms) <= 32
  ;;
  ;; Put another way, we can only double the minimum gap (1) 32 times before
  ;; we hit the largest allowed window.
  ;;
  ;; It's also worth noting that a mid-zoom can't be the 32nd zoom. There is no
  ;; way for a single remaining bit, after all the previous zooms, to have the
  ;; necessary condition of $low>2^30 and $high<=(2^31+2^30). So, the result
  ;; can be further restricted to:
  ;;
  ;; if $mid_zooms > 0: 0 <= ($outer_zooms + $mid_zooms) <= 31
  ;;
  ;; Now for the optimized algorithm:
  ;;
  ;; First, note that a "zoom high" emits a '1', and undergoes a "(x-HALF)*2"
  ;; The bit-pattern starts as: 0b1xx..xxx. The high bit is a '1' since it is
  ;; >= HALF. Subtracting HALF effectively clears that high bit, and the "*2"
  ;; shifts the remainder to the left leaving: 0bxx..xxx0. Which can be viewed
  ;; as "left shift, emit the bit falling off the left"
  ;;
  ;; Zoom lows are similar, except the high bit is a 0: 0b0yy..yyy. It is
  ;; similarly shifted, this time emiting a '0', leaving: 0byy...yyy0. Again,
  ;; it is "left shift, emit the bit falling off the left"
  ;;
  ;; And lastly, zoom mids work on values whose high bits are either 01 or 10
  ;; (Given the condition: QUARTER <= x < THREE_QUARTER)
  ;; The algorithm "(x-QUARTER)*2" first subtracts that QUARTER. Which changes
  ;; the high bits as: 01 -> 00, 10 -> 01. I.e. the high bit becomes '0', and
  ;; the 2nd high bit is flipped. Then it is bit shifted as above.
  ;;
  ;; Note that a high zoom is only possible when both $low and ($high-1) values
  ;; have a high bit of 1. (herafter, references to $high will actually be to
  ;; the value ($high-1) Similarly, a low zoom only happens when both
  ;; have a high bit of 0. To find the set of initial high/low zooms, we just
  ;; see how many high order bits both high and low have in common. Those
  ;; become the "known bits".
  ;;
  ;; After that initial set of matching high order bits, the next bit of low
  ;; and high will necessarily be different: low will have a 0, high a 1. A
  ;; "mid zoom" is possible if the following bit of high is a 0 (yielding 10),
  ;; and the following bit of low is a 1 (yielding 01). Additional mid-zooms
  ;; are possible so long as $high continues to have 0 bits, and $low continues
  ;; to have 1 bits.
  ;;
  ;; Consider the example:
  ;;
  ;; high = 0b10100100..
  ;; low  = 0b10011001..
  ;;
  ;; xor  = high ^ low
  ;;      = 0b00111101..
  ;;
  ;; The two leading zeros of that xor represent the "known bits" - that is,
  ;; we know we can zoom twice (in this case, once high, then once low).
  ;;
  ;; known_bits = clz(xor) // = 2 in this example
  ;;
  ;; After the zeros the xor will have a 1 bit where the low is necessarily a 0
  ;; and the high is a 1. After that, we want to know just how many cases exist
  ;; where low has a 1 while high has a 0.
  ;;
  ;; masked_xor = low & xor
  ;;      = 0b00011001..
  ;;
  ;; This represents a bit pattern where low has a 1 AND high has a 0. For the
  ;; first (known_bits + 1) bits, we know that the masked_xor will be zero
  ;; (For the first known_bits bits, the bits match so the condition won't be
  ;; met, and for the following bit we know low has a 0). After that, every
  ;; consecutive 1 bit is a valid mid-zoom.
  ;;
  ;; shifted_masked_xor = masked_xor << (known_bits + 1)
  ;;      = 0b11001..000
  ;;
  ;; Now with the 1 bits representing the mid-zooms at the left, we can invert
  ;; the pattern and count the leading zeros:
  ;;
  ;; mid_zooms = clz(~shifted_masked_xor) // = 2 in this example
  ;;
  ;; To summarize:
  ;;
  ;; xor = low ^ (high - 1)
  ;; known_bits = clz(xor)
  ;; mid_zooms = clz(~((xor & low) << (known_bits + 1)))
  ;;
  ;; That's 8 total operations with no branching for an algorithm that could
  ;; span a page with loops and branching if implemented in the naive way.
  ;; Pretty sweet!
  (func $zoom (export "_zoom")
    ;; Initial condition:
    ;;   0 <= low < mid < high <= 2^32 (where 2^32 is represented as 0)
    ;; Where "mid" is some i32 value that is between low and high (exclusively)
    ;;
    ;; Said another way: low < high-1
    ;;
    ;; The lower bound (inclusive). Between 0 and 2^32-2
    (param $low i32)
    ;; The upper bound (exclusive). Between 2 and 2^32 (note: 2^32 will be = 0)
    (param $high i32)

    ;; the # of known bits to shift
    (result i32)
    ;; the # of trailing mids
    (result i32)

    ;; the matching values of low/high
    (local $xor i32)
    ;; the # of "known" bits - i.e. the number of high or low zooms
    (local $known_bits i32)

    ;; DEBUG_START
    (local $dbg1 i32)
    (local $dbg2 i32)

    ;; DEBUG_END

    ;; xor = low ^ (high - 1)
    (local.set $xor
      (i32.xor (local.get $low) (i32.sub (local.get $high) (i32.const 1)))
    )

    ;; result: # of known bits
    ;; known_bits = clz(xor)
    (local.tee $known_bits (i32.clz (local.get $xor)))
    ;; result: # of mid zooms
    ;; = clz(~((xor & low) << (known_bits + 1)))
    (i32.clz
      (call $not32
        (i32.shl
          (i32.and (local.get $xor) (local.get $low))
          (i32.add (local.get $known_bits) (i32.const 1))
        )
      )
    )

    ;; DEBUG_START
    (local.set $dbg2)
    (local.set $dbg1)
    (call $log3 (i32.const 0xAF) (local.get $dbg1) (local.get $dbg2))
    (local.get $dbg1)
    (local.get $dbg2)
    ;; DEBUG_END
  )
)
