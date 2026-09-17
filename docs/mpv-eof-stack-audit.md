# MPV 硬解 EOF 现场栈分析（2026-09-09）

用户提供 LLDB `thread backtrace all`，原始附件以 thread 13 的部分帧开始，未包含最前面的线程。原文已保存在忽略目录 `output/user-mpv-eof-lldb-stack.txt`。

## 可以确认的事实

- thread 93，名称 core，在 libc 条件变量等待中，其 MPV 返回地址为 `0x5d32179db4`。
- thread 87 的符号化帧为 `mpv_wait_event + 712`，地址 `0x5d319b9dc4`。
- 当前库与里程碑 91 旧库的导出符号 `mpv_wait_event` 均为 ELF 地址 `0xbf9afc`。
- 因而模块加载偏移为 `0x5d319b9dc4 - 712 - 0xbf9afc = 0x5d30dc0000`，core 返回地址对应 ELF `0x13b9db4`。
- 两份库在 `0x13b9d84..0x13b9dcc` 的反汇编相同。`0x13b9db0` 调用 `pthread_cond_wait`，`0x13b9db4` 是返回后的指令。该调用由输出 FIFO 为空、`eof_sent` 非零、`decode_status` 为零的路径进入。
- 这里的 decoder 私有状态基址保存在 x29，output_mutex 为基址 +120，output_cond 为 +160，output_queue 指针为 +208，decode_status 为 +320，eof_sent 字节为 +324。

结论：现场采样直接定位到了 OHCodec receive_frame 的 EOF 输出等待。它会阻塞 MPV core 对后续控制请求的处理。单份快照尚不能证明没有后续唤醒，也不能判定 EOS 未回调、EOS 被丢失或解码器内部问题中的哪一种。

## 对候选修复的影响

此前 `tool/mpv_ohcodec_wakeup.S` 的候选方案处理输入等待与输出通知的竞争。现场停在另一个输出等待位置，不能用该补丁声称修复本次复现。该补丁尚未应用到播放器库或打入任何里程碑。

不提前跳过片尾，不将整个播放改成软解。下一步核对 core 状态与持续等待，研究保留末帧的 EOF 排空及退出处理。

## 可由现有 LLDB 会话补充的只读诊断

```text
thread select 93
frame select 2
register read x29 x22 x23
memory read --format x --size 4 --count 2 `$x29+320`
image list -o -f libmpv.so.2
```

若调试器提示该帧寄存器不可用，不猜测寄存器值或读取任意地址，应保留错误信息，改用汇编/寄存器可用帧定位。
