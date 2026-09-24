# MagicPad 1.1 性能架构评估

2026-09-24。对照源码 `htmlRev=20260924-dbg-h817`（`VERSION` 的 version 是 **1.1**，基线 genX = **1.0**）。只读，没有改产品代码，没有打包，没有用 Instruments，没有抓包，没有跑 `smoke-all`。

数字来自：`wc` / `du` / `gzip -c`、`MagicPadClient/index.html`、`MagicPadServer/Sources`。凡是没在这台机器上计时的，都标了 **未测**。

## 结论

滑动时的电和卡不在 Whisper，也不在 13 字节那一帧。`.app` 228MB 里有 221MB 是两套语音权重，但听写才加载；空闲触控板不该为它付钱。

手机真正的常驻开销是一条不停的 `requestAnimationFrame`。手指抬起以后，它仍在整屏淡出轨迹画布。按 3 倍屏估算，画布大约 300 万像素、约 11MB；每帧用 alpha 0.08 填满。GPU 时间 **未测**。

单指已经是「这一帧第一包马上发，其余并进现有 rAF」。双指滚动没有这道门：每个 `touchmove`（步长 ≥ 0.6px）发一帧 18 字节，Mac 上接着做一次辅助功能查询和一次滚轮事件。

手指光点每个 `touchmove` 都写 `left`/`top`，元素上还有 `backdrop-filter: blur(6px)`。这只烧手机合成，不该拿来改 Mac 光标。

Mac 热路径有两件已经做对：移动和滚动不进 MainActor，也不按帧写日志。还做在热路径上的是：每一帧移动、每一帧滚动都调用 `AXIsProcessTrusted()`。源码注释写过，`/health` 上这一下可以超过 2 秒。本机耗时 **未测**。

连上以后每 4 秒的 `/health` 会把整份 532KB 页面读进内存，只为抽出 `htmlRev`，并再查一次辅助功能。局域网这点流量不是问题。

草稿按字注入，每个字 `usleep` 6ms，和光标同一条队列。100 字大约堵住 0.6 秒的移动。这是发送时的卡，不是滑动时的耗电。

1.2 只做四件不动状态机的事：停掉空闲画布、手指点改走合成层、双指滚动沿用单指的「首包立即」合并、把辅助功能查询和 `htmlRev` 移出热路径。不要为了省电重写成 gen2。

流式听写、真 HID、拆掉单文件客户端，才配得上以后的 gen2。它们解决不了上面这四件。

## 1. 开销在哪

### 1.1 体积（磁盘，不是滑动）

| 东西 | 大小 | 说明 |
|---|---|---|
| `build/MagicPad.app` | 228MB | 菜单栏应用 |
| 其中 `Resources/whisper` | 221MB | 占应用 97% |
| `openai_whisper-base` | 144MB | 运行时优先这一套 |
| 其中 TextDecoder 权重 | 99.3MB | `weight.bin` |
| 其中 AudioEncoder 权重 | 39.3MB | `weight.bin` |
| `openai_whisper-tiny` | 77MB | base 齐全时运行时不用 |
| 其中 TextDecoder 权重 | 56.5MB | |
| 可执行文件 `MagicPadServer` | 6.2MB | 时间戳 2026-08-29，本次没拿它做采样 |
| `MagicPadClient/index.html` | 531766 字节，13026 行 | bundle 里同一份，520KB（du） |
| 同上，`gzip -c` | 113092 字节 | 本机压缩结果，线上没有 gzip |
| Swift 源码 | 7264 行 | 最大是 `EventInjector.swift` 1551、`WebSocketServer.swift` 1442 |

页面内部分：样式 3928 行 / 128478 字符（696 个块），脚本 8807 行 / 369170 字符（432 个 `function`、715 个 `try`），标记大约 293 行。样式里 `backdrop-filter` 30 处（另有 30 行 `-webkit-` 前缀），`box-shadow` 149 次，`@keyframes` 19 个，`@media` 34 个，其中 28 个是 `prefers-reduced-motion`。`will-change` 是 0。

base 的结构（`config.json`）：`d_model` 512，编解码各 6 层。tiny：`d_model` 384，各 4 层。`scripts/build_app.sh` 在 base 打进包之后仍会再打 tiny。`LocalWhisper.resolvedVariant()` 有完整 base 目录就只用 base。空闲时两套都只是磁盘。

### 1.2 手机：手指在板上

状态机没动，阈值仍是：`PRESS_HOLD_MS = 280`，`PRESS_HOLD_MAX_WIGGLE = 14`，`MOVE_PROMOTE_THRESHOLD = 36`（`index.html` 约 7376 行）。pending 只移光标，armed 才带左键，multi 不把滑动升成点击。下面说的都是这一套外面的绘制和发包。

`touchmove`（约 8037 行）对每个变化的触点做这些事：

1. 改写 `pointers` 里的坐标和抖动。
2. `showFinger`：设置 `style.left` / `style.top`，再 `refreshFingerRoles()`（`classList`，还 `querySelector('.finger-label')`）。光点 58×58，CSS 在约 881 行：`backdrop-filter: blur(6px)`，三层 `box-shadow`，`transform` 有 0.14s 过渡（过渡在缩放上，位置走的是 `left`/`top`，所以每事件触发布局）。
3. 单指：EMA 平滑后累加 `pendingDx/Dy`。`moveSentThisFrame` 为假时立刻 `flushPendingMove()`，并再挂一个 rAF 把标志清掉（约 8079 行）。这就是架构文档说的「同帧第一包立刻发，其余走现有 rAF」。不要再包一层过滤。
4. 双指滚动：步长 ≥ 0.6px 就 `sendGestureFrame(20, …)`（约 8169 行）。没有 `moveSentThisFrame` 这道门。死区 60px、提交额外 28px / 44px 仍在本地每事件算，那些阈值不要跟着合并改掉。
5. 捏合：相对缩放再变 22%（`pinchEmitRel`）才发 phase 21。不是每帧，但是每一档都是一次完整的 Cmd+= / Cmd+-。

`encodeFrame` 每次 `new ArrayBuffer(13)`（约 6170 行）。扩展帧 18 字节。WebSocket 客户端掩码后，单指一帧大约 19 字节、双指大约 24 字节（2 字节头 + 4 字节掩码 + 载荷）。**未抓包。** 60 次/秒也就是每秒 1KB 量级，带宽可以忽略。

单指一帧可能发两包：`touchmove` 发整像素，常驻 `loop()`（约 8498 行）再把余下的小数 flush 掉。上界大约是显示器刷新率的两倍。实际包率 **未测**。

`sendEvent` / `sendOrQueue` 每次都进 `bumpResumePing()`。不在恢复等待时，这个函数很快返回。它不是大头。

延迟回显：服务端对每个 ≥13 字节的二进制帧立刻回 6 字节（`sendLatencyEcho`）。手机 `binaryType = 'arraybuffer'`，`onmessage`（约 6001 行）每包都写 `#latency` 的 `textContent`。调试条默认 `class="debug hidden"`（约 4180 行），`display: none`。数字在变，人看不见。回显本身是延迟预算的探针，可以留着；每包改 DOM 没有必要。

分类 HUD：`noteClassify` 在滚动「武装」、捏合档位、松手判决时发一条 JSON，不是每个滚动像素一条。服务端 `handleText` 会把这条 JSON 写进日志（前 200 字）。频率低。

### 1.3 手机：页开着，但没碰

`loop()` 在启动时 `requestAnimationFrame(loop)`，没有退出条件（约 8563 行）。每一帧无条件 `fadeTrail()`：

- `CONFIG.trailFade = 0.92`，所以填充 alpha = 0.08。
- `fillRect` 覆盖 `window.innerWidth × innerHeight`。
- 画布按 `devicePixelRatio` 放大（`resizeCanvas`，约 4606 行）。逻辑 390×844、DPR 3 时是 1170×2532，约 296 万像素，RGBA 约 11.3MB。这是估算，不是这台手机的实测分辨率。
- 残留亮度大约 `0.92^n`。40 帧后约 4%，60 帧后约 0.7%。轨迹大约 1 秒就看不见了，循环却一直跑。
- 输入页（`mode-voice`）没有把这条循环停掉。听写、打草稿时画布仍在画。

手指按下时，同一帧里还有 `createRadialGradient` + `arc`。光点的 `left`/`top` 和这一帧读取 `innerWidth` 叠在一起，有机会把布局冲掉。布局耗时 **未测**。

这是手机侧最值得先做的一件事：它和 pending / armed / multi 无关，和 Mac 光标无关，页开着就在烧。

玻璃 UI（顶栏、按钮，大约 30 处背景模糊）是另一笔常驻合成。8 圈布局刚收工，1.2 不要整表重写。等有 Instruments 再决定砍哪些静止层。那仍然是 1.x，不是 gen2。

### 1.4 Mac：一帧进来以后

`WebSocketServer.accept` 的二进制回调（约 262 行）顺序是：

1. 在收包线程立刻回延迟 echo（不进 MainActor）。
2. `InjectRuntime`（`userInteractive` 串行队列）里 `consumeBinaryFrame`。
3. phase 1（移动）和 phase 20（滚动）不跳 MainActor。注释写明：以前每帧 hop 主线程就是卡顿来源。

`consumeBinaryFrame` 对 phase ≥ 10（含每一帧滚动）调用 `GestureTelemetry.note`：加锁、截断字符串、取一次 `Date`。不写日志文件。滚动不调用 `MagicLog`。

`injectMouse`（移动，约 346 行）每一帧：

1. `applyAcceleration`。当前档是 `.light`（系数 0.05），纯算术。
2. `hasAccessibilityPermission` → `AXIsProcessTrusted()`。
3. `CGEvent(source: nil)?.location` 读当前光标，加上加速后的 delta，再 `post` 一个 `.mouseMoved`（armed 之后才是 drag）。读光标是相对位移所必需的，不能为了省一次调用改成自己积分，否则和真实鼠标会漂。
4. 这一帧不写 `MagicLog`。

`injectScroll`（约 1384 行）每一帧：再查一次 `AXIsProcessTrusted()`，然后一个像素单位的 `scrollWheel` 事件。没有按帧日志。

辅助功能还在另外两处打：

- `AppState` 主线程 `Timer` 每 **1.0 秒** 查一次（`AppState.swift`）。
- `/health` 和每次 `hello` 再查一次。

`LANDetector.swift` 约 59 行的注释：`AXIsProcessTrusted in /health can exceed 2s`。这是以前为了防止 IP 和 URL 被这次调用拆开而写的，不是本次计时。三处可以同时打到同一个 API。若慢调用仍在，一次就会把注入队列堵住，光标跟着停。本机耗时 **未测**。所以这是「先量、再缓存」的项，不是闭眼加缓存。

捏合不在每帧热路径上，但每一档会堵住同一条队列。`postKeyChord` 里 `usleep` 合计 4+12+4+2 = **22ms**（约 1467 行），并且 `MagicLog` 打两次（`consumeBinaryFrame` 一次，`injectPinch` 一次）。`MagicLog.write` 每次 `new DateFormatter()`，再 `os.Logger`，再同步写 `/tmp/magicpad-server.log`。滑动的 phase 1/20 不走这里。右键、双击里的 `usleep`（右键路径有一次 55ms）是菜单能弹出的时序，不要当性能垃圾清掉。

`MagicLog` 在 Swift 源码里大约 179 处。滑动热路径不在其中。日志不是滑动电量的大头；捏合和 `/health` 的那几行值得改，因为 `DateFormatter` 不该在调用点现造。

### 1.5 连着的时候，每 4 秒

手机在连上后 `setInterval` 4000ms 调 `probeHealth`（约 8868 行）。服务端 `serveStaticFile`：

- `Cache-Control: no-store`，`Connection: close`。每次都是新 TCP，浏览器也不能把页面留下。
- `/health` 走 `healthJSON()`（约 1106 行）：`AXIsProcessTrusted()`；`StaticFileLocator.htmlRev()` → `loadIndexHTML()` 把 **整份 531766 字节**读成 `String` 再扫描 `MAGICPAD_HTML_REV`。
- 网卡快照有 8 秒 pin（`httpReaderPinTTL = 8`），所以不是每 4 秒都 `getifaddrs`。注释要求 `/health` 只读一次 `InstallEnvironment.healthLAN`；`healthJSON()` 仍是先读 `LANDetector`、中间插 AX、再读 `InstallEnvironment.current`。那是正确性遗留，不是这次要做的性能补丁。
- 没有 `Content-Encoding`。线上页面就是 532KB，不是 113KB。

手机收到 JSON 后，即使是 silent probe，仍会改辅助功能相关的 `classList`，并调用 `syncVoiceAxNote` / `syncHudTarget` / `checkHtmlRev`（约 5374 行，不在 `if (!silent)` 里面）。字段没变也会动 DOM。4 秒一次，不是滑动卡顿的原因，但是无意义的唤醒。

打开页面：手机要下载并解析 532KB、8800 行脚本、30 处背景模糊。解析时间 **未测**。这只发生在打开 / 硬刷，不发生在滑动中。`no-store` 是为了 `htmlRev` 能发现旧页，不能改成长期缓存；可以改为服务端按文件 mtime 把字节和 rev 留在内存，并给 HTML 做 gzip。

### 1.6 听写（不在滑动热路径，但是会独占机器）

`LocalWhisper` 是懒加载。`prefetchWeights()` 发现 base 目录已在就直接返回，不把模型送上 ANE。第一次转写才 `WhisperKit`：Mel 用 CPU+GPU，编码器和解码器用 CPU+ANE，`prewarm: true`，`load: true`（`makeKit`，约 329 行）。空闲 180 秒后 `kit = nil`。日志写 “keep RAM”，代码只是丢掉对象；ANE / 统一内存是否马上还回去 **未测**。

转写选项 `temperatureFallbackCount: 5`。难样本可能多次解码。一段话的墙钟时间 **未测**。不要为了省电在启动时预热模型——那会把空闲内存抬上去，和这次的目标相反。

两条路径都是「整段结束再识别」，不是流式：

- Mac 麦克风：`AVAudioEngine` tap（buffer 2048）把原采样率 WAV 写到临时文件，停录后再 `transcribe`。上限 55 秒。
- 手机录音：`MediaRecorder` 优先 `audio/mp4`，没有设码率；上传后 `AVAssetReader` 解成 16kHz 单声道 WAV。

base 权重里解码器 99MB、编码器 39MB，是听写那几秒的算力和内存。它不是触控板每帧的成本。换成 tiny 会伤识别，本次没有听写质量对比，**未测**，不要在 1.2 默认换小模型。

### 1.7 发送草稿时，光标队列被堵住

`injectText`（约 679 行）在注入队列上逐字 `keyboardSetUnicodeString`，每个字 `usleep` 3ms + 3ms。100 字约 **0.6 秒**，其间 `mouseMoved` 排在后面。这是同一条队列的设计（避免退格和点击乱序），不是泄漏。退格已经在手机侧按 24ms 合并次数，服务端仍按键 `usleep` 4ms + 间隔 6ms。

直达草稿的等待是 70ms 或 150ms（`LIVE_SETTLE_*`）。那是手感，不是开销，不要为了性能改短。

### 1.8 不是大头

- 协议帧本身（13 / 18 字节）和每秒 1KB 量级的回显。
- 单指 EMA、加速度系数 0.05。
- 热路径上的 `try/catch`（全文件 715 个）。不抛异常时可以忽略。
- Swift 6.2MB 二进制，相对 221MB 权重。
- 滚动惯性（最多 60 帧，衰减 0.92）和单指惯性。这是松手后的手感，约 1 秒，不是空闲常驻。空闲画布停掉时要把这段惯性跑完再停。
- 分类 JSON、8 秒一次的应用层 ping。

## 2. 1.2 起做什么

按收益 / 风险。每一项都不改 pending、armed、multi，不改 280ms / 14px / 36px，不新加一层「等 rAF 再发第一包」。

### 1. 没有手指、轨迹也淡完时，停掉 rAF

改 `loop()`：只在有触点、还有小数余量、或单指/滚动惯性还在跑时继续；轨迹用大约 60 帧（`0.92^60`）淡完就取消 rAF。`touchstart` 再挂上。输入页同样停。

为什么省：这是页开着就在做的整屏填充，和有没有在滑无关。听写时也在画一块看不见的画布。

手感：Mac 光标不变。板上的残影只要淡完再停，就不会突然截断。停早了残影会硬切，所以用帧数而不是抬手立刻停。

工作量：小。半天，含手机上看一眼残影。GPU 时间这次 **未测**，做完用 Safari 时间线看 rAF 是否归零即可，不必上 Instruments 才能开工。

### 2. 手指光点不要每事件触发布局

`showFinger` 改成每帧最多写一次位置，用 `translate3d`，不要给位移加 CSS 过渡（现有 0.14s 只留在出现时的缩放上）。去掉这个圆点的 `backdrop-filter: blur(6px)`。角色没变就不要 `querySelector`。

为什么省：滑动时主线程上最重的手机工作就是它。模糊还可能把背后一整层抓下来做backdrop。范围 **未测**，但 58px 的移动模糊没有产品职责。

手感：Mac 光标不经过这个 DOM。光点会少一层毛玻璃，位置仍跟手。若误把过渡加到位移上，点会拖在手指后面——那是唯一要避免的手感问题。

工作量：小。半天。和上一件分开提交，方便看是画布还是光点在耗。

### 3. 双指滚动沿用单指的合并规则

只合并 phase 20 的发送：这一帧第一包立刻发，同帧其余 delta 相加，下一帧再发。死区、提交阈值、右键/捏合判决仍在每个 `touchmove` 里算，不延迟。不要把捏合档位并进这个补丁。

为什么省：滚动现在是唯一按触摸投递率打满的输入。每包在 Mac 上是一次 AX 查询加一次 `CGEvent` 滚轮，手机侧是一次 18 字节分配和一次回显。投递率是 60 还是 120 **未测**；合并之后上界变成刷新率，总像素不变。

手感：风险中低。总位移还在，但单次滚轮的像素变大。要在「慢滑一行」和「快甩一页」上各看一次，并确认仍能区分右键（净位移小、时间短）和滚动。分类错了就是手感事故，所以判决逻辑保持每事件。

工作量：小到中。一天，含实机滚动，不要跑会注入按键的 `smoke-all`。

### 4. 辅助功能查询退出每一帧（先量）

在注入队列旁记一次 `AXIsProcessTrusted()` 的耗时（一次日志，不要每帧打）。若中位数可以忽略并且没有数秒的尖峰，这项降级，不要加缓存。若尖峰还在，注入路径只读一个布尔：侧边每 2–5 次/秒刷新，或直接用菜单栏那次 1 秒轮询的结果。`/health` 和 `hello` 用同一份，不要再各查一次。

为什么省：慢调用会堵住唯一的光标队列。注释已经把「超过 2 秒」写下来了。平时若是微秒级，收益就是去掉尖峰，不是降低平均 CPU。

手感：权限已经开着时，缓存几百毫秒到 1 秒没有区别。用户刚勾上或刚取消时，状态最多晚一个刷新周期。不要把「未授权」缓存到连系统设置都打不开。

工作量：量是小；确认有尖峰之后的改动也是小。没有计时之前不要做。

### 5. `/health` 不要每 4 秒读 532KB

`htmlRev()` 和 `loadIndexHTML()` 按文件 mtime 留在内存。页面字节同样留一份，提供 HTML 时不要每次 `Data(contentsOf:)`。gzip：`Accept-Encoding` 含 gzip 时把 HTML 压到大约 113KB（本机 `gzip -c` 的结果；线上往返 **未测**）。`no-store` 先留着，旧页检测还靠 `htmlRev`。

手机侧：silent probe 在 `ax` / `htmlRev` / `ip` 没变时不要改 `classList`。

为什么省：每 4 秒一次的分配和可能很慢的 AX，加上打开页面时多传约 4 倍的字节。不减少滑动时的包率。

手感：无。

工作量：小。不要借这个补丁把源码路径插到 bundle 前面。现在的顺序（环境变量 → 本 app 的 Resources → `/Applications` → 仅开发机源码树）是对的。热更新靠 mtime 缓存，不靠换搜索顺序。

### 6. 延迟数字不要每包写 DOM

回显继续每帧回（架构里的延迟探针）。`#latency` 只在调试条可见时更新，并且最多大约 4 次/秒。

手感：无。调试条默认隐藏。

工作量：很小。可以跟第 1 件一起做，也可以不做；收益远小于停画布。

### 7. 日志的时间格式化只造一次

`MagicLog.write` 和 `WebSocketServer.timestamp()` 各有一个现造的 `DateFormatter`。改成静态的。捏合不要打两行几乎相同的 `MagicLog`。不要给 phase 1/20 加日志。

手感：无。这不在滑动热路径上。

工作量：很小。优先级低于前四件。

### 8. 打字不要按字睡 6ms（放到 1.3，单独测）

`injectText` 把若干字放进同一次 `keyboardSetUnicodeString`，睡眠按批而不是按字。退格间隔不要和这件一起改。

为什么省：100 字约 0.6 秒内，触控板移动排在同一条队列后面。省的是发送时的卡，不是待机电量。

手感：有风险。有的输入框会吃掉连发的 Unicode。必须在文本框、中文输入法、验证码框里看，不能只看光标还能动。

工作量：中。一天，含打字测试。不要放进 1.2 的第一批。

### 明确排到更后面，而且仍是 1.x

- 静止玻璃层（30 处背景模糊）等 Instruments。刚做完布局，现在砍会把 8 圈的界面一起动掉。
- `temperatureFallbackCount: 5` 等有一段真实转写的耗时再降。降了可能伤难句。质量 **未测**。
- 不把 tiny（77MB）打进已经有完整 base 的包。省的是安装体积和备份，不是滑动的电。tokenizer 补齐逻辑要留。运行时本来就只加载一套。
- 不要在启动时预热 Whisper。那是用空闲内存换第一次听写的等待，和「降开销」相反。第一次加载要多久 **未测**。

## 3. 不要动

- **滑动升左键。** 禁止用移动距离把 pending 提成 `leftMouseDown`。`MOVE_PROMOTE_THRESHOLD`（36）、按住 280ms、抖动 14px、one-up 删掉另一指、断线松修饰键，都保持。第 3 件只合并滚轮包，不改判决。
- **不绑 LLM。** 听写仍是 WhisperKit / 必要时 Apple Speech。空结果不回退 Apple 是 1.1 的行为，性能工作不要把它改回去，也不要加云端模型。
- **不把家里的 IP、主机名、邮箱写回源码、二维码、文档或 `/health`。**
- **不为了热更新把源码路径插到 bundle 前面。** `StaticFileLocator` 现在只在「可执行文件就在本仓库的 `build/` 或 `MagicPadServer/` 下」时才看源码。装到别的机器必须走 bundle。要省的是重复读文件，不是换优先级。
- **不大拆 iOS 壳，不上蓝牙，不把 IOKit HID 当主路径。** `MagicPadIOS/HapticBridge.swift` 只有 62 行，网页触感在新系统上本来就弱；那是触感问题，不是这次的电量问题。真多点描述符是另一种产品。
- **不再包一层 rAF 把第一包推迟到下一帧。** 架构文档的延迟预算（触摸到 `CGEvent` 大约 13–20ms）是目标，本次 **未测**。合并只能丢掉同帧里的第二包及以后，第一包仍立即发。
- **不删滚动惯性，不缩短直达草稿的 70/150ms，不减右键/双击/捏合和弦里的 `usleep`。** 那些睡眠是菜单和修饰键不粘住的原因。
- **不把单文件拆成工程、不上打包器，只为了「看起来更现代」。** 打开时的解析成本用 gzip 和少做空闲绘制解决。拆文件不减少滑动时的 rAF。

## 4. 留在 1.x，还是才配 gen2

**留在 1.x（1.2、1.3…）。** 上面第 1–8 件，加上以后有仪器数据才做的玻璃层裁剪、转写回退次数、不打包 tiny。它们不改变协议（仍是 13/18 字节）、不改变状态机、不改变「CGEvent 而不是 HID」、不改变「单文件页面、扫码进局域网」。做完仍叫 1.x。不要因为动了画布或 AX 缓存就升 gen2。

**才配得上将来的 gen2**（现在不做，也不要用它们来代替 1.2）：

- 流式听写：边说边出字，替换「录完整段 WAV，再跑 base」。这会改 `SpeechSession` 和手机录音状态机，也会改等待手感。
- 真多点 HID 描述符，替换滚轮和 Cmd+/- 这种模拟。权限从「辅助功能」变成还要输入监控，三指的语义也会变。产品现在明确不做蓝牙 / Continuity。
- 放弃单文件页面，改成带构建步骤的客户端，或用原生壳重做触控板。只有当单文件大到无法改手感时才值得谈。它不解决空闲画布和每帧 AX。

降开销不是 gen2 的理由。1.2 的四件（停画布、光点、滚动合并、AX 与 `htmlRev` 移出热路径）做完，再决定要不要量玻璃和转写。量完仍不够，才考虑上面三件里的哪一件，并且单独起一版，而不是在 1.2 里顺手做。

## 附：本次没测到的

- 手机 GPU / CPU / 电量，空闲和滑动各一段。
- `AXIsProcessTrusted()` 在这台 Mac 上的中位数和尖峰。
- 单指、双指时的实际 WebSocket 包率（60Hz 还是 120Hz，一帧一包还是两包）。
- 端到端延迟是否还在 13–20ms。
- 打开页面的解析时间和 gzip 的真实往返（113092 只是本地 `gzip -c`）。
- Whisper 第一次加载的秒数、转写一段的秒数、`kit = nil` 之后内存是否下降。
- 批量 Unicode 注入会不会丢字。
- `build/MagicPad.app` 里的可执行文件时间戳是 2026-08-29，HTML 是 2026-09-24。没有把正在跑的进程当成 1.1 的性能样本。1.1 的空结果路由要等完整构建并重启才在进程里；那次改动本身不在热路径上。

## 落地（1.2，2026-09-24）

按上面第 1–5 件做了，仍是 1.x，不是 gen2。htmlRev `20260924-1.2-h818`。

做了：空闲轨迹大约 60 帧淡完就停 rAF，输入页不空跑；光点改 `translate3d` 并去掉那层 6px 模糊；phase 20 沿用单指的「本帧第一包立刻发」；htmlRev 和页面字节按 mtime 留内存，gzip 用同一份缓存；silent 探活在 ax / htmlRev / ip 没变时不改 classList。候选路径顺序没动。

AX 先量了：独立进程、userInteractive 串行队列，61 次中位数大约 0.001ms，最大大约 13ms，没有数秒尖峰。没有加缓存。注入队列上只在启动时打一行 9 次采样的日志。未授权不缓存，打开系统设置的路径没改。

没动：状态机和 36px / 280ms / 14px、按字睡 6ms、捏合档位、1.1 的 empty 不回退、LLM、家里 IP、真 HID、预热 Whisper、拆单文件。没跑 smoke-all。没杀正在跑的菜单栏进程。mtime 缓存和 gzip 要等下次完整构建并重启才在那个进程里；页面本身 html-only 已经换上。
