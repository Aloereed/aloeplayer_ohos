# 里程碑 88：系统投播入口可见性

版本：4.0.1+241。包含里程碑 87 的锁定按钮自动隐藏修复。

用户反馈系统投播入口空白，但点击对应位置仍能拉起系统选择器。原实现只使用 AVCastPicker 默认外观，未指定图标、颜色或文字，无法确保默认外观在嵌入视图内可见。

改用 AVCastPicker 的 customPicker，提供本地图播 SVG、白色文字和有对比度的实色背景。准备中显示灰色“正在准备投播…”，可用时显示蓝色“选择投播设备”。明确原生根组件尺寸，Flutter 引导文案对应按钮名称。点击仍由 AVCastPicker 处理，沿用原有会话与设备选择流程。

参考本地 SDK 的 @ohos.multimedia.avCastPicker.d.ets（customPicker API 12 起支持）及官方说明：https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V14/distributed-playback-guide-V14 。

验证：通过 HAP/APP 编译检查 ArkUI 自定义 Builder 和 SVG 资源引用；核验包版本及归档哈希。不访问用户设备，真机可见性和系统弹窗仍需用户确认。

包目录：build/milestones/88-system-cast-visible-picker，分别保存 debug 签名 HAP 与 release APP。
