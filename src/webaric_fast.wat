(module
  ;; IMPORT(utils.wat)
  (func $not32 (import "utils" "_not32") (param i32) (result i32))
  ;; IMPORT_END

  ;; Encode a range. This is the fundamental unit of work for the arithmetic
  ;; encoding.
  ;;
  ;; This works exactly like the standard (i.e."not fast") version except for
  ;; 1 big difference: This version never does mid zooms. Instead, it lets
  ;; the window size shrink all the way down to 1 if necessary to land in a
  ;; position where an outer zoom can be done. This removes a lot of corner
  ;; case handling, but it does negatively affect the compression. Values TBD.
  (func $encode_bit_fast (export "_encode_bit_fast")
    ;; State Parameters (initialized to 0 for 1st call, copied from previous call
    ;; for subsequent calls)
    ;;
    ;; Workspace
    (param $scratch i32)
    ;; 0 <= scratch_idx < 32
    (param $scratch_idx i32)

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
    (result i32)
    ;; scratch_idx
    (result i32)

    ;; Output results:
    ;;
    ;; the new low after all the zooms
    (result i32)
    ;; tyhe new high after all the zooms
    (result i32)
    ;; result_count. Either 0 or 1
    (result i32)
    ;; result: set if result_count > 0
    (result i32)

    (local $zooms i32)

    (if (result i32 i32 i32 i32 i32 i32)
      (local.tee $zooms (i32.clz (i32.xor (local.get $low) (local.get $high))))
      (then
        ;; we have zooms

        ;; set scratch with new data
        (local.set $scratch
          (i32.or
            (local.get $scratch)
            (i32.shr_u
              (i32.and
                (local.get $low)
                (call $not32 (i32.shr_u (i32.const -1) (local.get $zooms)))
              )
              (local.get $scratch_idx)
            )
          )
        )

        (local.tee $scratch_idx
          (i32.add (local.get $scratch_idx) (local.get $zooms))
        )

        i32.const 32
        i32.ge_u
        (if (result i32 i32)
          (then
            ;; spilled over the 32 bit boundary - need to grab the missing
            ;; bits of $low
            (i32.shl
              (i32.shr_u
                (i32.and
                  (local.get $low)
                  (call $not32 (i32.shr_u (i32.const -1) (local.get $zooms)))
                )
                (local.get $scratch_idx)
              )
              (local.get $zooms)
            )
            (i32.and (local.get $scratch_idx) (i32.const 0x1f))
          )
          (else
            (local.get $scratch)
            (local.get $scratch_idx)
          )
        )

        ;; apply the zoom levels
        (i32.shl (local.get $low) (local.get $zooms))
        (i32.shl (local.get $high) (local.get $zooms))
        (local.get $scratch)
        (i32.shr_u (local.get $scratch_idx) (i32.const 5))
      )
      (else
        ;; nothing to do
        (local.get $scratch)
        (local.get $scratch_idx)
        (local.get $low)
        (local.get $high)
        (i32.const 0)
        (i32.const 0)
      )
    )
  )
)
