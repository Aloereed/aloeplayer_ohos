# 里程碑 98：跨播放入口的 Surface 生命周期

版本 4.0.1+251。MPV 二进制保持里程碑 97 的版本。

用户反馈本地与 Emby 双向切换后只有声音。设备日志在 23:32:49 显示 EGL_BAD_MATCH（pixel format）及 eglCreateWindowSurface 失败，随后 current-vo 为空。日志证明画面输出初始化失败，尚不能单独确定全部触发条件。

修复插件中的三处具体缺陷：

- 新纹理先读取实际 ID，再设置正数 1×1 初始缓冲区，避免原先误操作 ID 0 和使用 0×0。
- 使用 Flutter OHOS 已实现的 unregisterTexture。当前 SDK 的 SurfaceTextureRegistryEntry.release 直接抛出未实现异常，旧代码未真正注销纹理。清理具备幂等性，忽略释放后的尺寸更新。
- 创建控制器时在同一锁内等待有效 Surface，设置 wid 后才启用 VO；后续 Surface 变化先关闭旧 VO 再重新绑定，避免并发初始化使用无效窗口。

验证：实际 VideoOutput.ets 经 TypeScript 转译的 100 次生命周期测试通过，包括新旧播放器重叠、重复释放、释放后更新、通道异常。Dart 静态检查无错误（有样式提示）。真实设备上本地→Emby→本地及 HDR 切换需用户实播确认；安装成功不等同于播放验证。
