# 中文标题与鸿蒙风格调整

## 29 — 中文标题

普通文件路径不再经过 URI.path 后直接显示；URI 使用解码后的 pathSegments，且只解码一次。普通文件名里的百分号和加号保留，媒体服务器提供的片名保留。新增 2 项回归通过，HAP 编译与 canonical 时间校验通过。

## 设计依据

- [HarmonyOS 官方设计](https://developer.huawei.com/consumer/cn/design)：空间层次、互动区域的沉浸光感。
- [设计理念](https://developer.huawei.com/consumer/cn/design/concept/)：蓝白色彩、舒适圆角、轻拟物与立体空间。
- [HarmonyOS 6](https://consumer.huawei.com/cn/harmonyos-6/)：自然、纯粹的光感表达。

应用采用 Flutter 自绘视觉，不声称调用了系统原生沉浸光感 API。光影集中于导航与重点卡片，避免给每个滚动条目叠加实时模糊。
