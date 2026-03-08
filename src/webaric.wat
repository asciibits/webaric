(module $webaric
  ;; (func (export "encode_bit_with_range")
  ;;   (param $win_low i32)
  ;;   (param $win_high i32)
  ;;   (param $val_low i32)
  ;;   (param $val_high i32)
  ;;   (param $num i32)
  ;;   (param $den i32)
  ;;   (param $bit i32)
  ;;   ;; win_low
  ;;   (result i32)
  ;;   ;; win_high
  ;;   (result i32)
  ;;   ;; val_low
  ;;   (result i32)
  ;;   ;; val_high
  ;;   (result i32)
  ;;   ;; bits
  ;;   (result i32)
  ;;   ;; num_bits
  ;;   (result i32)

  ;;   ;; short circuit for num==den - this implies 
  ;; )
  (func $_encode_bit
    ;; Invariant: $low < $mid < $high, except that a $high of 0 indicates
    ;; the value 2^32 - we just ran out of bits
    (param $low i32)
    (param $high i32)
    (param $mid i32)
    (param $bit i32)
    ;; if we are picking up from a mid-zoom
    (param $in_mid_zoom i32)
    ;; low
    ;; (result i32)
    ;; ;; high
    ;; (result i32)
    ;; ;; bits
    ;; (result i32)
    ;; ;; num_bits
    ;; (result i32)

    ;; Encoded bits
    (local $out_bits i32)
    ;; number of bits encoded
    (local $out_count i32)
    ;; number of trailing mid-zooms
    (local $mid_zooms i32)

    ;; (local.set $mid_zooms (local.get $in_mid_zoom))

    ;; use $bit to determine if we narrow our range to the upper or lower
    ;; portion
    ;; local.get $bit
    ;; (if
    ;;   ;; high range
    ;;   (then
    ;;     (local.set $low (local.get $mid))
    ;;   )
    ;;   ;; low range
    ;;   (else
    ;;     (local.set $high (local.get $mid))
    ;;   )
    )


  ;;   ;; zoom as needed
  ;;   (block $stop_zoom
  ;;     (loop $zoom_loop
  ;;       (i32.le_u (local.get $high) (i32.const 0x80000000))
  ;;       (if
  ;;         ;; this leaves 4 values on the stack
  ;;         (then call $_zoom_low)
  ;;         (else
  ;;           (i32.ge_u (local.get $low) (i32.const 0x80000000))
  ;;           (if
  ;;             (then call $_zoom_high)
  ;;             (else
  ;;               (i32.lt_u (local.get $low) (i32.const 0x40000000))
  ;;               br_if $stop_zoom
  ;;               (i32.gt_u (local.get $high) (i32.const 0xC0000000))
  ;;               br_if $stop_zoom
  ;;               call $_zoom_mid
  ;;             )
  ;;           )
  ;;         )
  ;;       )
  ;;       br $zoom_loop
  ;;     )
  ;;   )
  ;;   ;; We now have the additional invariant: $high-$low >= 0xC0000000

  ;;   local.get $low
  ;;   local.get $high
  ;;   local.get $out_bits
  ;;   local.get $out_count
  ;;   local.get $mid_zooms
  ;; )

  (func $_zoom_low (export "zoom_low")
    ;; Zoom low
    (param $low i32)
    (param $mid i32)
    (param $high i32)
    (param $mid_zooms i32)
    (param $need_leading_mid i32)

    ;; the new low
    (result i32)
    ;; the new mid
    (result i32)
    ;; the new high
    (result i32)
    ;; the new bits (need to be shifted and merged)
    (result i32)
    ;; the # of bits
    (result i32)
    ;; the new mid_zoom count
    (result i32)

    ;; Zooming low effectively doubles all values
    (i32.shl (local.get $low) (i32.const 1))
    (i32.shl (local.get $mid) (i32.const 1))
    (i32.shl (local.get $high) (i32.const 1))

    ;; We want a single '0' bit followed by $mid_zoom 1 bits, unless we
    ;; started in mid-zoom. In that case we do not want the leading zero
    (i32.shl
      (i32.sub
        (i32.shl (i32.const 1) (local.get $mid_zooms))
        (i32.const 1)
      )
      ;; shift left by 1 if we need the leading mid-zoom digit
      (local.get $need_leading_mid)
    )
    ;; we are pushing $mid_zooms plus 1 - but only add the extra 1 if
    ;; we need the leading mid digit
    (i32.add (local.get $mid_zooms) (local.get $need_leading_mid))
    
    ;; all mid-zooms are consumed
    i32.const 0
  )

  ;; (func $_zoom_high
  ;;   ;; Zoom high
  ;;   (param $low i32)
  ;;   (param $high i32)
  ;;   (param $mid i32)
  ;;   (param $bit i32)
  ;;   (param $in_mid_zoom i32)

  ;;   ;; the value to shift and add in to the bits
  ;;   (result i32)
  ;;   ;; the # of bits above to mix
  ;;   (result i32)
  ;;   ;; the new low
  ;;   (result i32)
  ;;   ;; the new high
  ;;   (result i32)
  ;;   ;; the new mid_zooms
  ;;   (result i32)

  ;;   (local $mid_zooms i32)
  ;;   (local $not_in_mid_zoom i32)
  ;;   (local.set $mid_zooms (local.get $in_mid_zoom))
  ;;   (local.set $not_in_mid_zoom
  ;;     (i32.xor (local.get $in_mid_zoom) (i32.const 1))
  ;;   )

  ;;   local.get $mid_zooms
  ;;   (if
  ;;     (result i32 i32)
  ;;     (then
  ;;       ;; we want to write a 0, followed by $mid_zooms 1 bits
  ;;       (i32.shl
  ;;         (i32.sub
  ;;           (i32.shl (i32.const 1) (local.get $mid_zooms))
  ;;           (i32.const 1)
  ;;         )
  ;;         ;; shift left by 1 if `in_mid_zoom` is *not* set
  ;;         (local.get $not_in_mid_zoom)
  ;;       )
  ;;       ;; we are pushing $mid_zooms plus 1 - but only add the extra 1 if
  ;;       ;; we are *not* starting in mid-zoom
  ;;       (i32.add (local.get $mid_zooms) (local.get $not_in_mid_zoom))
  ;;     )
  ;;     (else
  ;;       ;; write a single 0 bit
  ;;       i32.const 0
  ;;       i32.const 1
  ;;     )
  ;;   )
    
  ;;   ;; For the last two results, apply the new low/high
  ;;   (i32.shl (local.get $low) (i32.const 1))
  ;;   (i32.shl (local.get $high) (i32.const 1))
  ;;   ;; all mid-zooms are consumed
  ;;   i32.const 0
  ;; )

  ;; (func $_zoom_mid
  ;;   ;; Zoom low
  ;;   (param $low i32)
  ;;   (param $high i32)
  ;;   (param $mid i32)
  ;;   (param $bit i32)
  ;;   (param $mid_zooms i32)

  ;;   ;; the value to shift and add in to the bits
  ;;   ($result i32)
  ;;   ;; the # of bits above to mix
  ;;   ($result i32)
  ;;   ;; the new low
  ;;   ($result i32)
  ;;   ;; the new high
  ;;   ($result i32)
  ;;   ;; the new mid_zooms
  ;;   ($result i32)

  ;;   ;; A mid zoom doesn't add in any values until resolved
  ;;   i32.const 0
  ;;   i32.const 0

  ;;   ;; For the last two results, apply the new low/high
  ;;   (i32.shl (i32.sub (local.get $low) (i32.const 0x40000000)) (i32.const 1))
  ;;   (i32.shl (i32.sub (local.get $high) (i32.const 0x40000000)) (i32.const 1))
  ;;   ;; add 1 to the # of mid-zooms
  ;;   (i32.add (local.get $mid_zooms) (i32.const 1))
  ;; )
)
