; End-to-end test for Lumen v0.79+ systems, driver, and i48 fastcc extensions
; under the lumen vendor triple and "lumen" GC strategy:
;   llc tests/lumen_systems_driver.ll -o -
target triple = "x86_64-lumen-windows-gnu"

declare void @lumen_collect()

; 1. Unboxed 48-bit fastcc worker with tail-recursion elimination + gc "lumen"
define internal fastcc i48 @lmraw_acc(i48 %n, i48 %acc) gc "lumen" {
entry:
  %cmp = icmp sle i48 %n, 0
  br i1 %cmp, label %done, label %step

step:
  %n1 = sub i48 %n, 1
  %acc1 = add i48 %acc, %n
  %res = tail call fastcc i48 @lmraw_acc(i48 %n1, i48 %acc1)
  ret i48 %res

done:
  ret i48 %acc
}

; 2. Volatile MMIO load/store + x86 port I/O inline asm under gc "lumen"
define i64 @mmio_and_port_probe(ptr %mmio_reg) gc "lumen" {
entry:
  store volatile i32 305419896, ptr %mmio_reg, align 4
  %v = load volatile i32, ptr %mmio_reg, align 4
  call void asm sideeffect "outb $0, $1", "{al},{dx}"(i8 65, i16 1016)
  call void asm sideeffect "pause", ""()
  call void @lumen_collect()
  %ext = sext i32 %v to i64
  ret i64 %ext
}
