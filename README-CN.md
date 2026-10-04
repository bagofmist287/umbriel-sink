**Language / 语言：** [English](README.md) | [简体中文](README-CN.md)

# Umbriel Sink

Umbriel Sink 是一项关于平铺桌面交互的实验，受到[这场关于桌面体验的讲座](https://www.youtube.com/watch?v=V7AfAcQwLW0)启发。
它尝试验证一种对 Tiling 布局的补充：桌面怎样保存和表达用户刚刚离开的工作上下文，
让它们暂时离开当前工作面，却不从认知空间里彻底消失？

项目将这个问题收束为**短期工作上下文的挂起与恢复**，并以 [Umbriel](README-UMBRIEL.md) 为实验载体，
通过可恢复的 Sink/Pull 深度栈给出一种具体回答。普通桌面把这份上下文投影在当前工作面之后，
Overview 则展开同一个栈，便于辨认和选择。本项目不是 Noctalia 官方版本；
上游说明及常规构建、依赖文档保留在 [README-UMBRIEL.md](README-UMBRIEL.md)。

> **AI 参与声明：** 本 fork 的 Sink/Pull 功能、相关测试与脚本，以及本文档，均有 AI（OpenAI Codex）参与编写和修改。
> 使用前请结合实际设备与工作流自行检查；上游 Umbriel 的原始内容不应归因于本 fork 或 AI。

## Sink 能做什么

- `window-sink` 把当前焦点窗口压入所在 Workspace 的栈；`window-pull` 按后进先出顺序恢复栈顶窗口。
- Sunk 窗口保留原本的平铺/浮动归属、适用的窗口状态与 Workspace 占用，但不再接收普通输入或焦点。
  画面使用整窗投影表达深度，不为了缩小画面而要求客户端 resize。
- 普通桌面默认显示栈顶两层：深度 0 的缩放/透明度为 `0.93 / 0.82`，深度 1 为 `0.85 / 0.45`；
  更深的窗口仍在逻辑栈中，但越过可见边界（Horizon）。
- Overview 中，Sink 窗口的水平中心对齐所属 Workspace 预览，并位于平铺、浮动和普通全屏窗口之后。
  前 `visible_depth` 层露出可选择的顶部，更深层形成总高度有界的装饰尾部；前景适当下移以平衡展开后的画面，
  预留间距让相邻工作区预览保持分离。
- Overview 内也能 Sink/Pull，操作后保持 Overview 打开。栈变化只在局部推开卡片或填补空隙，不重播开场动画。
  点击或快捷确认 Sink 顶部入口时，会逐层解除覆盖它的 Sink 状态，并立即开始退出 Overview，
  与确认选择普通窗口的操作一致。
- Pull 恢复窗口的基础 Placement；普通桌面等待兼容的客户端提交后交付键盘焦点，Overview 内则继续
  持有键盘输入，直到退出。显式激活指定的 Sunk 窗口也能逐层解除覆盖它的 Sink 状态，遵循同一个内容屏障。

![Umbriel Sink 桌面演示截图](docs/media/sink_demonstration.png)

![Overview效果预览](docs/media/overview.png)

## 快速使用

按下文安装独立会话后，在登录界面选择 **Umbriel Sink**，不影响另行安装的官方 **Umbriel**。
仅编译源码不会自动更新已安装的会话二进制。

fork 专用配置位于 `~/.config/umbriel-sink/config.toml`。下面的示例继承已有 Umbriel 配置，
增加 Sink/Pull 键位，并显式列出普通桌面和 Overview 的默认设置：

```toml
[include]
files = ["../umbriel/config.toml"]

[keybinds]
"Mod+Alt+Down" = "window-sink"
"Mod+Alt+Up" = "window-pull"

[appearance.sink]
visible_depth = 2
levels = [
  { scale = 0.93, opacity = 0.82, blur_strength = 0.5 },
  { scale = 0.85, opacity = 0.45, blur_strength = 1.0 },
]
self_blur = false
blur_radius = 6
blur_samples = 9

[overview.sink]
exposure_height = 24
tail_height = 12
tail_decay = 0.5

[animation.overview.sink]
mode = "balanced"
```

这里的相对 `include` 继承基础配置的主题、快捷键和窗口规则，本文件中的同名设置最后覆盖继承值。
没有已有 Umbriel 配置时，请删除 `[include]` 并参考[完整示例配置](examples/config.toml)。
修改现有文件时，应把字段合并到已有表中，而不要重复声明同一个表。

Sink/Pull 绑定只留在 fork 专用文件中，不要写进两种会话共用的键位文件：上游 Umbriel 不认识这些动作。
上面的按键只是示例，请先检查自己的配置是否已占用。完整示例配置也包含 Sink/Pull 绑定，
按键选择应以自己的配置为准。

也可以从独立会话的终端直接发送动作，不依赖键位：

```sh
~/.local/libexec/umbriel-sink/umbriel-sink msg window-sink
~/.local/libexec/umbriel-sink/umbriel-sink msg window-pull
~/.local/libexec/umbriel-sink/umbriel-sink windows --json
```

`windows --json` 的 `sunk` 与 `sink_depth` 反映逻辑状态；`sink_depth = 0` 是栈顶，
并不代表任意深度都可见。更多动作和 IPC 字段见[动作](docs/user/actions.md)与 [IPC](docs/user/ipc.md) 文档。

## 桌面深度与 Overview 展示

`appearance.sink.visible_depth` 接受 1–4：普通桌面用它决定可见的整窗投影数，Overview 则用它决定
完整顶部入口数。更深的窗口仍在栈中，在 Overview 中仅以装饰尾部宣告存在，不增加直接选择入口。

`levels` 从近到远定义桌面样式。不填写时使用内建样式；自定义数组至少需要 `visible_depth` 个完整条目。
`scale` 限于 0.1–1，`opacity` 和 `blur_strength` 限于 0–1。Self Blur 模糊窗口自身内容，默认关闭；
开启后，`blur_strength` 决定本层使用多少比例的 `blur_radius`。半径范围为 1–32 逻辑像素，
`blur_samples` 范围为 3–17，偶数会降为前一个奇数。完整默认值见[外观配置](docs/user/appearance.md)。

完全打开 Overview 后，Sink 卡片按源尺寸参与 Overview 的整体缩放，独立的深度缩放、透明度衰减和
Self Blur 被取消。每个完整顶部露出最终预览画面中的 `exposure_height` 逻辑像素；窗口本身更矮时，
点击范围只取实际内容。更深层逐次减小露出高度，让展开总高度保持有界：

| 字段 | 默认值 | 含义 |
| --- | --- | --- |
| `exposure_height` | `24` | 每个可选择顶部的高度，1–256 逻辑像素。 |
| `tail_height` | `12` | 装饰尾部合计高度上限，0–256；设为 0 不露出尾部。 |
| `tail_decay` | `0.5` | 相邻尾层新增高度的比例，严格大于 0、小于 1。 |

前景下移量取栈实际展开总高度的一半。Overview 在组织预览时预留配置允许的 Sink 容量和窗口边界，
局部 Sink/Pull 不改变相邻间距，也为原本空栈的工作区第一次 Sink 留出空间。

`animation.overview.sink.mode` 决定普通桌面与 Overview 之间的展示交接：

| 档位 | 尺寸、展开与前景下移 | 独立深度透明度与 Self Blur |
| --- | --- | --- |
| `performance` | 立即切换。 | 打开时立即取消，关闭时立即恢复。 |
| `balanced`（默认） | 随 Overview 渐变。 | 打开时立即取消，关闭时立即恢复。 |
| `smooth` | 随 Overview 渐变。 | 随同一个进度渐变。 |

所有渐变共用 Overview 的实际进度并一起结束，中途反向也使用同一映射；三档不使用逐层延迟，
不增加独立时长。关闭全局或 Overview 动画时直接到位。Overview 内局部 Sink/Pull 沿用
`animation.windows_move`，`performance` 或相关动画关闭时局部变化也直接到位。
需要完整效果交接时使用 `mode = "smooth"`；自模糊仍须 `appearance.sink.self_blur = true`，
单独选择 `smooth` 不会开启它。
交互细节见 [Overview 中的 Sink](docs/user/workspaces-overview.md#sink-in-overview)。

三至四层桌面投影尤其配合 Self Blur 可能增加 GPU 开销。现有性能测量主要覆盖默认两层，
不能直接推断扩展层数的成本或三个档位间的帧率差异。修改配置后可校验并热重载：

```sh
~/.local/libexec/umbriel-sink/umbriel-sink validate -c ~/.config/umbriel-sink/config.toml
~/.local/libexec/umbriel-sink/umbriel-sink msg config-reload
```

## 构建并安装独立会话

首次构建可沿用上游 [README-UMBRIEL.md](README-UMBRIEL.md#building) 的依赖说明。
本 fork 的独立会话使用专门的 Release 构建，不运行 `just install` 去覆盖官方 Umbriel：

```sh
meson setup build-sink-release --buildtype=release -Db_lto=true -Dtests=disabled -Dcpp_std=c++23 --prefix="$HOME/.local"
meson compile -C build-sink-release umbriel
```

已有 `build-sink-release/` 时只需第二条命令。更新二进制与配置前请先退出正在运行的 Umbriel Sink 会话。
下列路径是建议的独立安装布局，不会替代官方 Umbriel；`build*/` 和 `compile_commands.json`
已被 [`.gitignore`](.gitignore) 忽略，构建产物不应提交或强制添加到 Git。

| 仓库文件 | 建议安装位置 / 用途 |
| --- | --- |
| `build-sink-release/umbriel` | `~/.local/libexec/umbriel-sink/umbriel-sink`，独立合成器二进制 |
| [`tools/sink-session/start-umbriel-sink`](tools/sink-session/start-umbriel-sink) | `~/.local/bin/start-umbriel-sink`，登录启动器 |
| [`tools/sink-session/umbriel-sink.service`](tools/sink-session/umbriel-sink.service) | `~/.config/systemd/user/umbriel-sink.service`，用户服务 |
| [`tools/sink-session/umbriel-sink.desktop.in`](tools/sink-session/umbriel-sink.desktop.in) | 登录界面入口模板，安装时生成用户专属的 `Exec` 路径 |
| [`tools/sink-session/install-session-entry.sh`](tools/sink-session/install-session-entry.sh) | 渲染模板，并以管理员权限安装独立会话入口 |
| fork 专用配置 | `~/.config/umbriel-sink/config.toml`，可 `include` 官方配置 |

首次安装时，先准备上文的 fork 专用配置，然后把二进制、启动器和用户服务安装到表中路径：

```sh
install -Dm755 build-sink-release/umbriel "$HOME/.local/libexec/umbriel-sink/umbriel-sink"
install -Dm755 tools/sink-session/start-umbriel-sink "$HOME/.local/bin/start-umbriel-sink"
install -Dm644 tools/sink-session/umbriel-sink.service "$HOME/.config/systemd/user/umbriel-sink.service"
systemctl --user daemon-reload
```

已有独立安装时，退出会话后重新构建并替换专用二进制。配置应与程序使用同一版接口：
将旧动画 `type` 设置改为 `mode` 和上表中的值，重新登录前用新安装的程序校验。

会话入口由模板生成，不在仓库里保存任何人的 home 目录路径。可先预览渲染结果，确认无误后安装：

```sh
tools/sink-session/install-session-entry.sh --render
tools/sink-session/install-session-entry.sh
```

脚本默认从 `$HOME` 解析 `~/.local/bin/start-umbriel-sink`，运行时才写入系统会话目录；
若启动器位于别处，可把不含空格或特殊符号的绝对路径作为脚本参数。
脚本会调用 `sudo`，不会覆盖官方会话项。会话隔离与路径细节见
[`tools/sink-session/README.md`](tools/sink-session/README.md)。登录入口和 fork 服务不会修改官方
`umbriel.desktop`、`umbriel.service`、`start-umbriel` 或官方配置文件。

## 代码、测试与现状

Sink 栈和桌面展示主要位于 `src/workspace/sink_stack.h`、`src/workspace/sink_presentation.h`、
`src/workspace/workspace.cpp` 与 `src/scene/window_projection.*`；Overview 卡片、几何与共同过渡在
`src/overview/overview.*` 和 `src/overview/sink_layout.*`。配置解析在 `src/config/`，Self Blur 渲染在 `umbrielfx/`。

GPU harness 覆盖桌面 Sink/Pull、投影与 Self Blur，以及 Overview 的居中、层级、入口、间距、
动画档位、局部操作和生命周期交接。Overview 专项按 `overview_sink` 分组，其中
`382_overview_sink_style_transition.sh` 检查实际尺寸、透明度与模糊渐变；
真实应用试运行脚本为 [`tests/manual/sink_real_apps.sh`](tests/manual/sink_real_apps.sh)。

```sh
just test debug
just check 155_sink_logic 156_sink_projection 158_sink_self_blur overview_sink
```

GPU harness 需要可用的 DRM render node；只有构建或纯逻辑单测通过，不等于实际 GPU/原生 seat 验收。
核心 Sink/Pull 和 Overview 展示已实现；原生日常体验、Self Blur 与扩展可见层数仍处于个人试用与性能调优阶段。
上游许可见 [LICENSE](LICENSE)；此 fork 的变更同样应遵守仓库许可证。
