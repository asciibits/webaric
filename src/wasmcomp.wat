(module
  ;; IMPORT(utils.wat)
  (func $not32 (import "utils" "_not32") (param i32) (result i32))
  (func $log1 (import "utils" "_log1") (param i32))
  (func $log2 (import "utils" "_log2") (param i32 i32) (result i32))
  (func $log3 (import "utils" "_log3") (param i32 i32 i32) (result i32 i32))
  (func $log4 (import "utils" "_log4")
    (param i32 i32 i32 i32)
    (result i32 i32 i32)
  )
  ;; IMPORT_END

  ;; Calculate the number of times we can "zoom" into a windowed region.
  ;;
  ;; The range considered is all possible i32 values for both $low and $high.
  ;; 0 <= $low <= $high < 2^32
  ;;
  ;; Every "zoom" represents doubling the gap between $high and $low. We
  ;; consider only three potential zooms:
  ;;
  ;; "zoom low": both $low and $high are in the bottom half of i32 values
  ;; (i.e. their leading bit is a 0). In this case, both values are doubled,
  ;; and we record a "zoom_low". Note: because the values are alread <= 2^31,
  ;; doubling their values keeps them within the i32 range.
  ;;
  ;; "zoom high": both $low and $high are in the top half of i32 values (i.e.
  ;; their leading bit is a 1). In this case, we first subtract 2^31, then
  ;; double, and we record a "zoom_high". By subtracting 2^31 first, we keep
  ;; the resulting values in the i32 range.
  ;;
  ;; "zoom mid": both $low and $high are between the "quarter" and "three
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
  ;; mid_zooms count.
  ;;
  ;; Another simplification is that the initial set of high/low zooms will
  ;; look very similar to the bit pattern of $low and $high. We only zoom
  ;; high if both have a leading 1 bit. And we only zoom low if both have a
  ;; leading 0 bit. So, we could just return the leading bit pattern; Or, even
  ;; easier, just the number of available high/low zooms and let the caller
  ;; pull the bit pattern out of $low or $high.
  ;;
  ;; So, this function can return two i32 values: "outer_zooms" (i.e. the number
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
  ;; way for a single remaining bit, after 31 previous zooms, to have the
  ;; necessary condition of $low>=2^30 and $high<(2^31+2^30). So, the result
  ;; can be further restricted to:
  ;;
  ;; if $mid_zooms > 0: 0 <= ($outer_zooms + $mid_zooms) <= 31
  ;;
  ;; Now for the optimized algorithm:
  ;;
  ;; First, note that a "zoom high" emits a '1', and undergoes a "(x-2^31)*2"
  ;; The bit-pattern starts as: 0b1xx..xxx. The high bit is a '1' since it is
  ;; >= 2^31. Subtracting 2^31 effectively clears that high bit, and the "*2"
  ;; shifts the remainder to the left leaving: 0bxx..xxx0. Which can be viewed
  ;; as "left shift, emit the bit falling off the left"
  ;;
  ;; Zoom lows are similar, except the high bit is a 0: 0b0yy..yyy. It is
  ;; similarly shifted, this time emiting a '0', leaving: 0byy...yyy0. Again,
  ;; it is "left shift, emit the bit falling off the left"
  ;;
  ;; And lastly, zoom mids work on values whose high bits are either 01 or 10
  ;; (Given the condition: 2^30 <= x < (2^31+2^30))
  ;; The algorithm "(x-2^30)*2" first subtracts that 2^30. Which changes
  ;; the high bits as: 01 -> 00, 10 -> 01. I.e. the high bit becomes '0', and
  ;; the 2nd high bit is flipped. Then it is bit shifted as above.
  ;;
  ;; Note that a high zoom is only possible when both $low and $high values
  ;; have a high bit of 1. Similarly, a low zoom only happens when both
  ;; have a high bit of 0. To find the set of initial high/low zooms, we just
  ;; see how many high order bits both $high and $low have in common. Those
  ;; become the "outer zooms".
  ;;
  ;; After that initial set of matching high order bits, the next bit of $low
  ;; and $high will necessarily be different: $low will have a 0, $high a 1. A
  ;; "mid zoom" is possible if the following bit of $high is a 0 (yielding 10),
  ;; and the following bit of $low is a 1 (yielding 01). Additional mid-zooms
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
  ;; The two leading zeros of that $xor represent the "outer zooms" - that is,
  ;; we can zoom twice (in this case, once high, then once low).
  ;;
  ;; outer_zooms = clz(xor)  ;; = 2 in this example
  ;;
  ;; After the zeros the $xor will have a 1 bit where $low is necessarily a 0
  ;; and $high is a 1. After that, we want to know just how many cases exist
  ;; where $low has a 1 while $high has a 0.
  ;;
  ;; masked_xor = low & xor
  ;;      = 0b00011001..
  ;;
  ;; This represents a bit pattern where $low has a 1 AND $high has a 0. For
  ;; the first ($outer_zooms + 1) bits, we know that the $masked_xor will be zero
  ;; (For the first $outer_zooms bits, the bits match so the $xor will be 0, and
  ;; for the following bit $low will be 0). After that, every consecutive 1 bit
  ;; is a valid mid-zoom.
  ;;
  ;; shifted_masked_xor = masked_xor << (outer_zooms + 1)
  ;;      = 0b11001..000
  ;;
  ;; Now with the 1 bits representing the mid-zooms at the left, we can invert
  ;; the pattern and count the leading zeros:
  ;;
  ;; mid_zooms = clz(~shifted_masked_xor)  ;; = 2 in this example
  ;;
  ;; To summarize:
  ;;
  ;; xor = low ^ high
  ;; outer_zooms = clz(xor)
  ;; mid_zooms = clz(~((xor & low) << (outer_zooms + 1)))
  ;;
  ;; That's 7 total operations with no branching for an algorithm that could
  ;; span a page with loops and branching if implemented in the naive way.
  ;; Pretty sweet!
  ;;
  ;; Following any mid zooms, if we just shift without fixing the leading bits, we
  ;; end up with:
  ;;
  ;; 0 <= $high < 2^31 <= $low < 2^32
  ;;
  ;; Interestingly, in this case, the above logic holds. We will always get a 0
  ;; for $outer_zooms, and the correct # for any viable mid zooms.
  (func $zoom (export "_zoom")
    ;; Initial condition:
    ;;   0 <= low <= high < 2^32
    ;;
    ;; The lower bound (inclusive)
    (param $low i32)
    ;; The upper bound (inclusive)
    (param $high i32)

    ;; the # of leading outer zooms
    (result i32)
    ;; the # of trailing mid zooms
    (result i32)

    ;; the matching values of low/high
    (local $xor i32)
    ;; the # of leading outer zooms
    (local $outer_zooms i32)

    ;; xor = low ^ high
    (local.set $xor (i32.xor (local.get $low) (local.get $high)))

    ;; result: outer_zooms = clz(xor)
    (local.tee $outer_zooms (i32.clz (local.get $xor)))
    ;; result: # of mid zooms
    ;; = clz(~((xor & low) << (outer_zooms + 1)))
    (i32.clz
      (call $not32
        (i32.shl
          (i32.and (local.get $xor) (local.get $low))
          (i32.add (local.get $outer_zooms) (i32.const 1))
        )
      )
    )
  )

  ;; Encode a range. This is the fundamental unit of work for the arithmetic
  ;; encoding.
  ;;
  ;; This function is designed to be called in a processing loop, though it does
  ;; no looping or recursion on its own.
  ;;
  ;; For input, it takes a series of "state" values. These should be initialized
  ;; to zero on the first call, and passed from this functions output on
  ;; subsequent calls.
  ;;
  ;; This function is comlicated by the need to process an unknown number of mid
  ;; zooms. A low zoom emits a 1, a high zoom emits a 0, but a mid-zoom could be
  ;; either and won't be resolved until the next high/low zoom. In a 1TB file
  ;; we might expect to have runs of mid-zooms up to maybe 20 (this assumes that
  ;; the chance of a mid-zoom is ~1/4). Getting a run of 30 is exceedingly
  ;; unlikely. But still this algorithm must account for the possiblity.
  ;;
  ;; To handle this corner case, this algorithm keeps track of at least 32 and up
  ;; to 63 such unresolved mid zooms (total number depends on exactly where in
  ;; mod 32 the start of the mid-zooms falls). After the storage for these zooms
  ;; is exhausted, no more mid zooms are allowed, allowing the $high/$low window
  ;; to shrink below the normal min of 2^30. As that window shrinks, the fidelity
  ;; of the compression drops, eventually reaching 0 compression if the window
  ;; gets to size 1. At that point, up to 32 bits of low/high zooms will be
  ;; generated, allowing the mid-zooms to be resolved, and resetting the dangling
  ;; mid-zoom counter to 0. In affect, this contingency will never get hit
  ;; (outside of heavily tuned test code) and won't impact compression. Also,
  ;; it will be evealuated as an extremely unlikely branch, allowing near zero
  ;; performance loss as the CPUs branch predictors do their job.
  (func $encode_bit (export "_encode_range")
    ;; State Parameters (initialized to 0 for 1st call, copied from previous call
    ;; for subsequent calls)
    ;;
    ;; Workspace
    (param $scratch i64)
    ;; Current position within $scratch. 0 <= scratch_idx < 64
    (param $scratch_idx i64)
    ;; 0 <= dangling_idx <= scratch_idx
    (param $dangling_idx i64)

    ;; Params
    ;;
    ;; Note the input requirements:
    ;;   following a normal zoom: 0 <= $low <= $high < 2^32
    ;;   following a mid-zoom:    0 <= $high < 2^31 <= $low < 2^32
    ;;
    ;; The lower bound (inclusive)
    (param $low i32)
    ;; The upper bound (inclusive)
    (param $high i32)

    ;; State Results
    ;;
    ;; scratch
    (result i64)
    ;; scratch_idx
    (result i64)
    ;; dangling_idx
    (result i64)

    ;; Output results:
    ;;
    ;; the new low after all the zooms
    (result i32)
    ;; tyhe new high after all the zooms
    (result i32)
    ;; result_count. Either 0, 1, or (rarely) 2
    (result i64)
    ;; result: set if result_count > 0
    (result i64)

    (local $outer_zooms i32)
    (local $zooms i32)
    (local $tmp i64)

    (call $zoom (local.get $low) (local.get $high))
    ;; temporarily mid-zooms - to be added with outer zooms shortly
    local.set $zooms
    local.set $outer_zooms

    (if (result i64 i64 i64 i32 i32 i64 i64)
      (local.tee $zooms (i32.add (local.get $zooms) (local.get $outer_zooms)))
      (then
        ;; we have zooms

        ;; set scratch with new data
        (local.set $scratch
          (i64.or
            (local.get $scratch)
            (i64.shr_u
              (i64.shl
                (i64.extend_i32_u
                  (i32.and
                    (local.get $low)
                    (call $not32 (i32.shr_u (i32.const -1) (local.get $zooms)))
                  )
                )
                (i64.const 32)
              )
              (local.get $scratch_idx)
            )
          )
        )

        (if (result i64 i64 i64 i32 i32 i64 i64)
          (local.get $outer_zooms)
          (then
            ;; Check for previously dangling mid-zooms
            (if
              (i64.gt_u (local.get $scratch_idx) (local.get $dangling_idx))
              (then
                ;; resolve the dangling mids by adding one bit to the current
                ;; scratch idx
                (local.set $scratch
                  (i64.add
                    (local.get $scratch)
                    (i64.shr_u
                      (i64.const 0x8000000000000000) (local.get $scratch_idx)
                    )
                  )
                )
              )
            )
            (local.set $dangling_idx
              (i64.add
                (local.get $scratch_idx)
                (i64.extend_i32_u (local.get $outer_zooms))
              )
            )
            (local.set $scratch_idx
              (i64.add
                (local.get $scratch_idx) (i64.extend_i32_u (local.get $zooms))
              )
            )

            ;; Calculate the $scratch and $scratch_idx
            (if (result i64 i64)
              (i64.ge_u (local.get $scratch_idx) (i64.const 64))
              (then
                ;; spilled over the 64 bit boundary - need to grab the missing
                ;; bits of $low
                (local.set $tmp
                  (i64.shl
                    (i64.shr_u
                      (i64.extend_i32_u
                        (i32.and
                          (local.get $low)
                          (call $not32
                            (i32.shr_u (i32.const -1) (local.get $zooms))
                          )
                        )
                      )
                      (local.get $scratch_idx)
                    )
                    (i64.extend_i32_u (local.get $zooms))
                  )
                )
                (if (result i64 i64)
                  (i64.ge_u (local.get $dangling_idx) (i64.const 64))
                  (then
                    (local.get $tmp)
                    (i64.and (local.get $scratch_idx) (i64.const 0x1f))
                  )
                  (else
                    (i64.or
                      (i64.shl (local.get $scratch_idx) (i64.const 32))
                      (i64.shr_u (local.get $tmp) (i64.const 32))
                    )
                    (i64.and (local.get $scratch_idx) (i64.const 0x3f))
                  )
                )
              )
              (else
                (i64.shl
                  (local.get $scratch)
                  (local.tee $tmp
                    (i64.and (local.get $dangling_idx) (i64.const 0x300))
                  )
                )
                (i64.sub (local.get $scratch_idx) (local.get $tmp))
              )
            )

            ;; The remaining results
            (i64.and (local.get $dangling_idx) (i64.const 0x1f))
            (i32.shl (local.get $low) (local.get $zooms))
            (i32.shl (local.get $high) (local.get $zooms))
            (local.get $scratch)
            (i64.shr_u (local.get $dangling_idx) (i64.const 5))
          )
          (else
            (local.set $scratch_idx
              (i64.add
                (local.get $scratch_idx) (i64.extend_i32_u (local.get $zooms))
              )
            )
            (if
              (i64.gt_u (local.get $scratch_idx) (i64.const 63))
              (then
                ;; make sure the zooms don't overflow 64 bits. This is absurdly
                ;; unlikely. In this case, clamp zooms and scratch_idx
                (local.set $zooms
                  (i32.sub
                    (local.get $zooms)
                    (i32.sub
                      (i32.wrap_i64 (local.get $scratch_idx))
                      (i32.const 63)
                    )
                  )
                )
                (local.set $scratch_idx (i64.const 63))
              )
            )
            ;; no outer_zooms - leave the dangling_idx and move the scratch_idx
            ;; but don't allow scratch_idx to overwrite $scratch
            (local.get $scratch)
            (local.get $scratch_idx)
            (local.get $dangling_idx)
            (i32.shl (local.get $low) (local.get $zooms))
            (i32.shl (local.get $high) (local.get $zooms))
            (i64.const 0)
            (i64.const 0)
          )
        )
      )
      (else
        ;; nothing to do
        (local.get $scratch)
        (local.get $scratch_idx)
        (local.get $dangling_idx)
        (local.get $low)
        (local.get $high)
        (i64.const 0)
        (i64.const 0)
      )
    )
  )
)
