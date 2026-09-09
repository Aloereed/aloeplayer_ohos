# 里程碑 74：媒体服务器首页与详情选集（4.0.1+227）

服务器列表的两个入口统一进入首页，独立展示媒体库、继续观看、下一集、最新入库与收藏。每个分区独立加载和重试，部分接口失败不隐藏其他结果；除返回全部媒体库的 Views 外，其余分区提供“查看全部”分页页面。所有读取可取消，刷新保留已有首页内容。

影片与剧集海报进入详情，显示简介、时长、年份、分级、评分、类型与演职人员；提供续播、从头播放、收藏及已看操作，变更以服务器回复后的查询结果为准，失败明确显示。系列展示季度选择、剧集详情入口与分页选集。切季取消旧请求，迟到结果不会覆盖新季；离开详情取消未完成的详情和播放协商。

普通媒体库中从详情返回只更新对应海报，保留已加载列表和滚动位置。媒体库首页入口在自身根目录返回时直接回到首页，不额外展开全部服务器目录。

兼容策略：Jellyfin 使用当前用户库路由，404/405 时回退到旧用户路径；Emby 使用其稳定用户路径。401/403/服务器错误不触发兼容回退。账号只通过请求头发送令牌；反向代理前缀保留；列表不请求完整 MediaSources。收藏使用 POST/DELETE，已看与未看使用对应用户状态接口。

协议参考：
- https://github.com/jellyfin/jellyfin/blob/master/Jellyfin.Api/Controllers/UserViewsController.cs
- https://github.com/jellyfin/jellyfin/blob/master/Jellyfin.Api/Controllers/UserLibraryController.cs
- https://github.com/jellyfin/jellyfin/blob/master/Jellyfin.Api/Controllers/ItemsController.cs
- https://github.com/jellyfin/jellyfin/blob/master/Jellyfin.Api/Controllers/TvShowsController.cs
- https://dev.emby.media/reference/RestAPI/TvShowsService/getShowsByIdSeasons.html

本机 HTTP 用例分别验证 Jellyfin/Emby 的认证、路径前缀、状态操作方法与分页参数；界面用例覆盖分区故障隔离、失败操作不显示假成功、关闭取消、快速切季。真实服务器版本组合与鸿蒙实机仍未验证；完整播放源/字幕/转码、连续播放、离线与高级筛选继续推进，不能以此里程碑声明总目标已完成。
