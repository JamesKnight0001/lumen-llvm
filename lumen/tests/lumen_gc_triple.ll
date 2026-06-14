; Test the Lumen-specific LLVM modifications:
;  1. the "lumen" triple vendor  (x86_64-lumen-windows-gnu)
;  2. the gc "lumen" strategy     (registered, lowers cleanly)
;
; The Lumen frontend keeps roots in entry-block allocas (no @llvm.gcroot), so
; the strategy just needs to be a recognized GC name that marks safepoints and
; lowers without error at any opt level.

target triple = "x86_64-lumen-windows-gnu"

declare void @lumen_collect()

; A function tagged gc "lumen": holds a value in a stack slot across a call into
; the collector, exactly the shape the Lumen backend emits.
define i64 @rooted(i64 %v) gc "lumen" {
entry:
  %slot = alloca i64
  store i64 %v, ptr %slot
  call void @lumen_collect()
  %r = load i64, ptr %slot
  ret i64 %r
}
