// AArch64 replacement for the exact MPV revision gated by repair_mpv_wakeup.py.
// No frames, timestamps, codec options, or EOF results are changed.
// Lock order is input -> output everywhere, including output publication.
.text
.global callbacks
callbacks:
// onNeedInputBuffer(codec, index, buffer, AVCodecContext *userdata)
    stp x19, x20, [sp, #-48]!
    stp x21, x30, [sp, #16]
    str w1, [sp, #32]
    str x2, [sp, #40]
    mov x19, x3
    ldr x20, [x3, #32]
    add x0, x20, #24
    bl mutex_lock
    ldr x0, [x20, #112]
    add x1, sp, #32
    mov w2, #1
    bl fifo_write
    mov w21, w0
    add x0, x20, #64
    bl cond_signal
    add x0, x20, #24
    bl mutex_unlock
    tbz w21, #31, 1f
    mov x2, x19
    mov w1, #1
    bl on_error
1:
    ldp x21, x30, [sp, #16]
    ldp x19, x20, [sp], #48
    ret

.global wait_input_or_output
wait_input_or_output:
// Called with input mutex held. Recheck output before atomically releasing
// input mutex and sleeping: an output callback now also takes input mutex.
    stp x19, x20, [sp, #-32]!
    stp x21, x30, [sp, #16]
    mov x19, x0
    mov x20, x1
    sub x21, x1, #24
    add x0, x21, #120
    bl mutex_lock
    ldr x0, [x21, #208]
    bl fifo_can_read
    mov x21, x0
    add x0, x20, #96
    bl mutex_unlock
    cbnz x21, 2f
    mov x0, x19
    mov x1, x20
    bl cond_wait
2:
    mov w0, #0
    ldp x21, x30, [sp, #16]
    ldp x19, x20, [sp], #32
    ret

// Preserve the address already registered for onNewOutputBuffer.
.org 188
.global output_callback
output_callback:
    stp x19, x20, [sp, #-48]!
    stp x21, x30, [sp, #16]
    str w1, [sp, #32]
    str x2, [sp, #40]
    mov x19, x3
    ldr x20, [x3, #32]
    add x0, x20, #24
    bl mutex_lock
    add x0, x20, #120
    bl mutex_lock
    ldr x0, [x20, #208]
    add x1, sp, #32
    mov w2, #1
    bl fifo_write
    mov w21, w0
    add x0, x20, #160
    bl cond_signal
    add x0, x20, #120
    bl mutex_unlock
    add x0, x20, #64
    bl cond_signal
    add x0, x20, #24
    bl mutex_unlock
    tbz w21, #31, 3f
    mov x2, x19
    mov w1, #1
    bl on_error
3:
    ldp x21, x30, [sp, #16]
    ldp x19, x20, [sp], #48
    ret
.org 392
