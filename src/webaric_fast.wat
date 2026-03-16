(module
  ;; DEBUG_START
  (func $log1 (import "test" "log1") (param i32))
  (func $log2 (import "test" "log2") (param i32 i32))
  (func $log3 (import "test" "log3") (param i32 i32 i32))
  (func $log4 (import "test" "log4") (param i32 i32 i32 i32))
  (func $log5 (import "test" "log5") (param i32 i32 i32 i32 i32))
  (func $log6 (import "test" "log6") (param i32 i32 i32 i32 i32 i32))
  (func $log64_1 (import "test" "log64_1") (param i32))
  (func $log64_2 (import "test" "log64_2") (param i32 i32))
  (func $log64_3 (import "test" "log64_3") (param i32 i32 i32))
  (func $log64_4 (import "test" "log64_4") (param i32 i32 i32 i32))
  (func $log64_5 (import "test" "log64_5") (param i32 i32 i32 i32 i32))
  (func $log64_6 (import "test" "log64_6") (param i32 i32 i32 i32 i32 i32))
  ;; DEBUG_END

  ;; IMPORT(utils.wat)
  (func $min32 (import "utils" "_min32") (param i32 i32) (result i32))
  (func $not32 (import "utils" "_not32") (param i32) (result i32))
  (func $make2x32 (import "utils" "_make2x32") (param i32 i32) (result v128))
  (func $get2x32 (import "utils" "_get2x32") (param v128) (result i32 i32))
  ;; IMPORT_END

  ;; Encode a single bit, with its associated $mid position; that is, the
  ;; position between $low and $high that represents a low and high zoom
  ;; respectively.
  ;;
  ;; This function is designed to be called in a processing loop, though it does
  ;; no looping or recursion on its own.
  ;;
  ;; For input, it takes a series of "state" values. These should be initialized
  ;; to zero on the first call, and passed from this functions output on
  ;; subsequent calls.
  ;;
  ;; This implementation favors speed over compression, and does not attempt to
  ;; resize the zoom window unless the next bit can be determined. This means no
  ;; "mid zooms".
  ;;
  ;; State parameters (initialize to 0 on first call, pass back in the result
  ;;   state on subsequent calls):
  ;; i32 $low          : The (inclusive) lower bound for the current window
  ;; i32 $high         : The (inclusive) upper bound for the current window
  ;; i32 $scratch      : Scratch space
  ;; i32 $scratch_idx  : The position within scratch after all currently
  ;;                     resolved zomms (i.e. before and dangling zooms)
  ;;
  ;; Note the invariant:
  ;;   0 <= $low < $mid <= $high < 2^32
  ;;
  ;; Input parameters:
  ;; i32 $mid : A value between $low (exclusive) and $high (inclusive). A value
  ;;            closer to $high represents a high probability of a 1 bit, and
  ;;            vice versa.
  ;; i32 $bit : The bit to encode
  ;;
  ;; State results (see State parameters):
  ;;    $low, $high, $scratch, $scratch_idx, $dangling_idx
  ;;
  ;; Output results:
  ;; i32 $has_results: 1 if $result has data, 0 otherwise
  ;; i32 $result     : 32 bits of output data, if $result_count == 1
  (func $encode_bit (export "_encode_bit")
    ;;
    ;; State values
    ;;
    ;; The lower bound (inclusive)
    (param $low i32)
    ;; The upper bound (inclusive)
    (param $high i32)
    ;; Workspace
    (param $scratch i32)
    ;; 0 <= scratch_idx < 32
    (param $scratch_idx i32)
    ;; A value between $low and $high - the new boundary based on $bit
    (param $mid i32)
    ;; the value to encode
    (param $bit i32)

    ;; the new low after all the zooms
    (result i32)
    ;; tyhe new high after all the zooms
    (result i32)
    ;; scratch
    (result i32)
    ;; scratch_idx
    (result i32)
    ;; result_count. Either 0, 1, or (rarely) 2
    (result i32)
    ;; result: set if result_count > 0
    (result i32)

    (local $outer_zooms i32)
    (local $result_count i32)
    (local $result i32)

    ;; process the bit and reset the range
    (local.tee $low
      (select (local.get $low) (local.get $mid) (local.get $bit))
    )
    (local.tee $high
      (select (local.get $mid) (local.get $high) (local.get $bit))
    )
    i32.xor
    i32.clz
    local.tee $outer_zooms

    (if (result i32 i32)
      (then
        ;; we have an outer zoom

        ;; set the outer-zooms
        (local.set $scratch
          (i32.or
            (local.get $scratch)
            (i32.shr_u
              (local.get $low)
              (local.get $scratch_idx)
            )
          )
        )

        (local.tee $scratch_idx
          (i32.add
            (local.get $scratch_idx)
            (local.get $outer_zooms)
          )
        )

        i32.const 32
        i32.ge_u
        (if
          (then
            ;; Leave this branch - it is predictably weighted to the `else`
            (local.set $result (local.get $scratch))
            (local.set $result_count (i32.const 1))
            (local.set $scratch_idx
              (i32.sub (local.get $scratch_idx) (i32.const 32))
            )
            (local.set $scratch
              (i32.and
                (i32.shl
                  (local.get $low)
                  (i32.sub (local.get $outer_zooms) (local.get $scratch_idx))
                )
                (call $not32
                  (i32.shr_u (i32.const -1) (local.get $scratch_idx))
                )
              )
            )
          )
        )

        ;; apply the zoom levels
        (i32.shl (local.get $low) (local.get $outer_zooms))
        (i32.shl (local.get $high) (local.get $outer_zooms))
      )
      (else
        (local.get $low)
        (local.get $high)
      )
    )

    ;; state
    ;; low/high from the giant if block above
    (local.get $scratch)
    (local.get $scratch_idx)

    ;; actual results
    (local.get $result_count)
    (local.get $result)
  )
)
