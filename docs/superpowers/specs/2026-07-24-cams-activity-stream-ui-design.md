# cams「活动」推流页 UI 改造设计

- **日期**: 2026-07-24
- **范围**: `surveillance/cams` 模块「活动」tab(`ActivityStreamScreen`)及其相关推流管线
- **状态**: 待评审

## 1. 背景与问题

「活动」tab(`selectedTab === 2`,渲染 `ActivityStreamScreen`)是手机摄像头推流(IP 摄像头模式)的控制页,支持 RTSP(本地服务)与 RTMP(推到服务器)两种模式。当前存在 4 个问题:

1. **预览/暂停按钮语义混淆** —— 控件用 `isStreaming ? ⏸ : ▶`,即"未推流显示 ▶、推流中显示 ⏸"。但 `▶` 这个图标在"预览已自动播放"的场景下误导用户:按钮实际控制的是**推流的启停**,不是预览的播放/暂停。用户期望按钮控制的是"预览(摄像头画面)"本身。
2. **静音按钮点击无效** —— `isMuted` 仅切换本地图标状态,**从未接入任何音频管线**。核查确认:当前推流是**纯视频(H264)**管线,从采集、编码到网络封包的任何一层都没有音频轨道(native `librtspencoder.so` 只创建视频编码器、`CMakeLists.txt` 未链接 `libnative_media_aenc.so`、`RtspServer.buildSdp` 只有 `m=video`、`RtmpPushManager` 只发 video tag type=9)。设置里的"采集麦克风音频"开关同理是个死开关。
3. **全屏仍显示标题栏/底部菜单栏** —— `ActivityStreamScreen` 的全屏(`isFullscreen`)只把中间区域横屏铺满,但顶部 `NvrMainTopBar` 和底部 `NvrBottomBar` 由 `MainPage` 包裹,全屏时未隐藏。
4. **「视频设置」是页面内的折叠面板** —— 当前分辨率/画质/帧率/推流方式/地址等是一个常驻折叠面板(`settingsExpanded`),占位大、与"播放页"形态不符。

## 2. 目标

- 让推流控件语义清晰、按钮真实可用;
- 全屏真正沉浸式;
- 「视频设置」收敛为播放页上的一个按钮菜单;
- 把音频管线从无到有搭建起来,使「静音」按钮真正控制推流音频轨的有无。

## 3. 用户决策(已确认)

| 决策点 | 选择 |
|---|---|
| #1 按钮语义 | 按钮**控制预览**(camera 预览开关),而非推流启停 |
| #2 静音 | **搭建完整音频管线**(native + RTSP/RTMP 音频轨) |
| #3 全屏 | **隐藏顶栏 + 底栏** |
| #4 视频设置形态 | **底部弹出面板(Bottom Sheet)** |
| 音频参数 | **44100Hz / 立体声 / AAC-LC** |
| 静音实现 | **编码器热切换**(采集与编码器持续运行,静音时送静音 PCM/不送 AAC 帧) |
| 音频开关入口 | **只用静音按钮**,移除设置里的"采集麦克风音频"死开关 |

## 4. 架构总览

### 4.1 模块划分

改动按「职责隔离」拆为 5 个边界清晰的单元:

| 单元 | 文件 | 职责 |
|---|---|---|
| **A. 音频采集+编码(native)** | `cpp/audio_encoder_engine.{h,cpp}` + `napi_init.cpp` + `Index.d.ts` + `CMakeLists.txt` | 麦克风 PCM 采集(`OH_AudioCapturer`)→ AAC-LC 编码(`OH_AudioEncoder`)→ 回调 AAC 帧 |
| **B. RTSP 音频轨** | `utils/RtspServer.ets` | SDP 增加 `m=audio` 段;新增 `sendAacData()`;AAC 的 RTP 分片(mpeg4-generic) |
| **C. RTMP 音频轨** | `utils/RtmpPushManager.ets` | audio sequence header(AudioSpecificConfig)+ audio data tag(type=8) |
| **D. 推流编排** | `utils/CameraStreamManager.ets` | 启停音频 capturer/encoder;音频帧分发到 B/C;静音热切换;MICROPHONE 权限 |
| **E. Activity UI** | `components/NvrSecondaryScreens.ets` + `pages/MainPage.ets` | #1 预览按钮、#2 静音按钮接线、#3 全屏隐藏栏、#4 设置 Bottom Sheet |

### 4.2 数据流(推流音频路径)

```
[麦克风 PCM] --OH_AudioCapturer--> [AudioEncoderEngine (AAC-LC)]
   --napi tsfn--> onAudioFrame(AacFrame{data, pts, config?})
   --CameraStreamManager--> isMuted ? 丢弃 : sendAacData()
        |--(RTSP)--> RtspServer.sendAacData() --> AAC RTP (PT=97, mpeg4-generic)
        |--(RTMP)--> RtmpPushManager.sendAacData() --> audio tag (type=8)
```

视频路径保持不变(`VideoEncoderEngine` → `sendH264Data`)。

## 5. 详细设计

### 5.1 #1 预览按钮 —— 控制预览(语义修正)

**当前**:图标 `isStreaming ? ⏸pause : ▶play`,onClick 切换推流(`startStream/stopStream`)。

**改为**:图标语义改为控制**预览**:
- 预览运行中 → 显示 `⏸ pause`(点击暂停预览)
- 预览未运行 → 显示 `▶ play`(点击启动预览)

新增 manager 接口 `pausePreview()` / `resumePreview()`(区别于现有的 `pauseStream()`/`resumeStream()` 是给后台切换用的、会释放全部相机资源):

> **决策点(实现时定,不阻塞设计)**:是否真的需要一个轻量级"暂停预览(冻结画面但保留 session)",还是复用 `restartPreview`/释放相机?倾向:轻量级 `session.stop()` + 恢复 `session.start()`,保留 input/output,不重建 session。若 HarmonyOS VideoSession 不支持此轻量切换,则退化为"释放并重建"(等同 `restartPreview`)。此选择不影响 UI 语义。

推流启停改由现有的 **Toggle 开关**(底部渐变层 `推流中/未推流` 旁的开关)和全屏底部的 play/pause 按钮承担。全屏底部按钮保留 `isStreaming ? ⏸ : ▶` 语义(控制推流),与内嵌预览按钮职责区分。

> **注意**:内嵌预览底部原本有两个推流入口(图标按钮 + Toggle)。改为:预览底部的图标按钮 → 控制预览;Toggle → 控制推流。避免两个控件抢同一职责。

**预览与推流的依赖关系(重要)**:视频推流依赖 camera 预览(session)运行,因此:
- 推流中时,预览按钮**置灰禁用**(不能在推流时暂停预览),提示「请先停止推流」。
- 停止预览(暂停 session)时,若正在推流,先 `stopStream()` 再暂停预览。
- 音频管线独立于 camera session(麦克风不依赖相机),不受预览暂停影响 —— 但预览通常意味着整路推流停止,音频也随之停止(见 §5.2.4 编排:`stopStream` 会同时关音频)。

这样三态清晰:① 仅预览(预览开、推流关)② 推流中(预览开且锁定、推流开)③ 全停(预览关、推流关)。

### 5.2 #2 音频管线(native + 协议 + 编排 + UI)

#### 5.2.1 native(`AudioEncoderEngine`)

**新增文件** `src/main/cpp/audio_encoder_engine.h` / `.cpp`:

- 类 `AudioEncoderEngine`,接口对称于 `VideoEncoderEngine`:
  - `create(sampleRate=44100, channelCount=2, bitrate=128000)` → 启动采集+编码,返回内部句柄(音频无 surface,返回成功标志字符串如 `"ok"` 或空串表示失败)
  - `start()` / `stop()` / `release()`
  - `setCallback(env, callback)` —— tsfn 回调 `AacFrame { data: ArrayBuffer, pts: number, isConfig: boolean }`(`isConfig` 标识该帧是 AudioSpecificConfig,首帧必发)
  - `setMuted(muted: boolean)` —— **热切换**:muted 时 capturer 持续读取并丢弃 PCM(保持采样率/pts 连续),不喂给编码器;取消静音时恢复正常喂入。这样编码器始终运行,取消静音无重连延迟。
- 采集:`OH_AudioCapturer`(`OH_AudioStream_SourceType.SOURCE_TYPE_MIC`),PCM 16-bit,采样率 44100,声道 2。
- 编码:`OH_AudioEncoder_CreateByMime("audio/mp4a-latm")`,AVCodec 回调模式;首输出帧若带 `CODEC_DATA` 标记则作为 `isConfig=true` 的配置帧(AAC-LC 的 AudioSpecificConfig,2 字节)。

**改动** `napi_init.cpp`:新增全局 `AudioEncoderEngine* g_audioEncoder`;注册 `createAudioEncoder / startAudioEncoder / stopAudioEncoder / releaseAudioEncoder / setAudioEncoderMuted` 五个导出。

**改动** `Index.d.ts`:
```ts
export const createAudioEncoder: (sampleRate: number, channelCount: number, bitrate: number, callback: (frame: AacFrame) => void) => string;
export const startAudioEncoder: () => void;
export const stopAudioEncoder: () => void;
export const releaseAudioEncoder: () => void;
export const setAudioEncoderMuted: (muted: boolean) => void;
export interface AacFrame { data: ArrayBuffer; pts: number; isConfig: boolean; }
```

**改动** `CMakeLists.txt`:
- `add_library` 增加 `audio_encoder_engine.cpp`
- `target_link_libraries` 增加 `libnative_media_aenc.so`(AAC 编码器)+ `libohaudio.so`(`OH_AudioCapturer`)

> **编译验证限制**:win32 环境无法编译 HarmonyOS native。此部分交付后需在 DevEco/真机编译验证。我会严格参照现有 `VideoEncoderEngine` 的范式实现,降低出错概率。

#### 5.2.2 RTSP 音频轨(`RtspServer.ets`)

- `buildSdp()` 增加(在 `m=video` 段之后):
  ```
  m=audio 0 RTP/AVP 97\r\n
  a=rtpmap:97 mpeg4-generic/44100/2\r\n
  a=fmtp:97 streamtype=5;profile-level-id=1;mode=AAC-hbr;sizelength=13;indexlength=3;indexdeltalength=3\r\n
  a=control:track1\r\n
  ```
  payload type 96=video, 97=audio。
- 新增 `sendAacData(frame: Uint8Array, timestamp: number, isConfig: boolean)`:按 mpeg4-generic RTP 封装(AU-headers section + AAC payload),PT=97,时钟频率=44100。config 帧(AudioSpecificConfig)通常不单独 RTP 发送(SDP/RTMP 会带),但保留接口。
- RTP 打包复用现有 `sendRtpPacket`/`sendUdpRtpPacket`,但需为音频 track 维护独立的序列号/时间戳。现状:`sendNaluToClient` 内对 video track 的 seq/timestamp 字段在 `RtspClient` 上;需确认是否在 client 上新增 audio 的 seq/timestamp 字段(实现时按现有 `RtspClient` 结构扩展)。

#### 5.2.3 RTMP 音频轨(`RtmpPushManager.ets`)

- `sendConnect` 已声明 `audioCodecs: 4071`(AAC 支持),此前是空头声明,本次落地。
- 新增 `sendAacData(frame: Uint8Array, timestamp: number, isConfig: boolean)`:
  - `isConfig=true`:发 audio sequence header —— audio tag,`tagData[0]=0xAF`(AAC, 44100, stereo),后续跟 2 字节 AudioSpecificConfig(`0x12 0x10` 对应 AAC-LC 44100 stereo)。
  - `isConfig=false`:发 audio data tag —— `tagData[0]=0xAF`,后续跟 `0x01`(AAC raw data)+ AAC 帧。msgType=8(audio),csid=4,timestamp=音频 pts。
- 首个 AAC 编码帧(`isConfig=true`)必须先于 data tag 发送(客户端据此解码)。

#### 5.2.4 编排(`CameraStreamManager.ets`)

- `startStream()`:在创建视频 encoder 之后,创建音频 encoder(`createAudioEncoder(44100, 2, 128000, cb)`),`onAudioFrame` 回调里 `if(!this.audioMuted) sendAacData(...)`。音频不依赖 camera session,可独立启停。
- `stopStream()` / `pauseStream()` / `resumeStream()`:`releaseAudioEncoder()` / 重建。音频生命周期与视频对齐。
- 新增 `setAudioMuted(muted: boolean)`:设 `this.audioMuted` 并调用 native `setAudioEncoderMuted(muted)`(热切换)。
- `ensurePermissions()`:扩展为同时请求 `ohos.permission.CAMERA` 与 `ohos.permission.MICROPHONE`(权限已声明于 `module.json5`)。麦克风权限被拒时:音频管线跳过,推流仍可继续(纯视频降级),静音按钮置灰或提示。
- `aboutToAppear` 时把 `isMuted` 初值同步给 manager。

#### 5.2.5 UI 接线(`NvrSecondaryScreens.ets`)

- 静音按钮 onClick:`this.isMuted = !this.isMuted; this.streamManager?.setAudioMuted(this.isMuted);`(全屏 + 内嵌两处)。
- 移除设置面板里的"采集麦克风音频"开关(`rtmpAudioEnabled` 相关 UI 块,约 L1634-1652)及其 props 链路(MainPage → ActivityStreamScreen 的 `rtmpAudioEnabled` 透传)。注意:`rtmpAudioEnabled` 在 `NvrUiState`/`NvrViewModel` 中也有引用,清理时连带处理(保留字段以免破坏持久化 schema,仅移除 UI 与读取)。

### 5.3 #3 全屏隐藏顶栏 + 底栏

**`MainPage.ets`**:
- `ActivityStreamScreen` 新增回调 `onFullscreenChange: (isFullscreen: boolean) => void`(或复用 `@Link`/`@Provide`-`@Consume`)。倾向**回调**,与现有 `onTabSelected` 等回调风格一致。
- `MainPage` 新增 `@State activityFullscreen: boolean = false`,`enterFullscreen`/`exitFullscreen` 时通过回调置位。
- `build()` 中:当 `this.activityFullscreen` 为真,跳过 `this.MainTopBar()` 与 `NvrBottomBar(...)` 的渲染,让 `ActivityStreamScreen` 占满整个 `Column`。
- `Stack` 最外层保留,使全屏视频铺满;横屏方向由 `ActivityStreamScreen.enterFullscreen()` 已有的 `setPreferredOrientation(LANDSCAPE)` 控制。

> **退出路径**:全屏内有返回箭头(`chevron_left` → `exitFullscreen`)和右下缩放图标,均会触发回调复位顶/底栏。

### 5.4 #4 视频设置 → 底部弹出面板(Bottom Sheet)

- 新增 `@State settingsSheetVisible: boolean = false`。
- 移除页面常驻的「视频设置」折叠面板(`settingsExpanded` 整块,含分辨率/画质/帧率/推流方式/地址/手电筒/变焦/二维码)。
- 在预览区的右侧按钮列(现有"切换/比例/全屏")新增一个「设置」按钮(`sys.symbol.slider_horizontal_3` 或 `gearshape`),onClick 打开 sheet。
- 全屏底部控制栏也加一个「设置」图标按钮,onClick 打开 sheet(全屏下 sheet 浮于视频之上)。
- Bottom Sheet 实现:用 `bindSheet`(`.bindSheet($$this.settingsSheetVisible, this.StreamSettingsSheet())`)——HarmonyOS ArkUI 原生底部弹层,自带半透明遮罩、下滑关闭、动效,无需手写。Sheet 内容 builder `StreamSettingsSheet()` 复用现有分辨率/画质/帧率/推流方式/地址/手电筒/变焦/二维码的 builder 代码(平移,不重写逻辑)。
- 二维码(RTSP 地址)可放进 sheet,或保留为独立项(实现时定)。

> 「人体检测」开关与「活动日志」是独立区块,不属于"视频设置",保留在主页面流,不进 sheet。

## 6. 错误处理 / 降级

| 场景 | 处理 |
|---|---|
| 麦克风权限被拒 | 音频管线跳过,纯视频推流;静音按钮禁用 + toast 提示「未授予麦克风权限,无法推流音频」 |
| native audio encoder 创建失败 | 同上降级;log error;不影响视频推流 |
| setAudioMuted 热切换失败 | 仅本地状态,下次 startStream 重试 |
| bindSheet 不可用(老版本) | 退化为自定义 Stack 遮罩面板(实现时按目标 API 判断) |
| 暂停预览(session 轻量切换)不支持 | 退化为释放并重建(restartPreview) |

## 7. 验证计划

| 项 | 方法 | 环境 |
|---|---|---|
| #1 #3 #4(ArkTS UI) | DevEco 预览/真机运行,手动验证按钮语义、全屏隐藏栏、sheet 弹出 | 真机/模拟器 |
| #2 视频(回归) | 确认视频推流未因音频改动而破坏(RTSP 播放器拉流看画面) | 真机 |
| #2 音频(RTSP) | VLC/ffplay 拉本地 RTSP,确认有声音、静音按钮可切换无声 | 真机 |
| #2 音频(RTMP) | 推到测试 RTMP 服务器,ffplay/浏览器拉流确认音视频同步 | 真机 |
| native 编译 | DevEco 构建 cpp target,确认 `libnative_media_aenc.so`/`libohaudio.so` 链接通过 | DevEco |
| 静音热切换 | 推流中反复点静音/取消,VLC 确认声音中断/恢复无爆音、无延迟卡顿 | 真机 |

> **本环境限制声明**:win32 无法编译/运行 HarmonyOS(native 与 ArkTS 均不能在此验证)。所有验证需在 DevEco Studio + 真机/模拟器完成。代码交付为"尽力实现 + 严格遵循现有范式",最终正确性以真机为准。

## 8. 风险

- **R1(native 音频)**:`OH_AudioCapturer` + `OH_AudioEncoder` 的异步回调/线程模型与现有视频 surface 模式不同,实现复杂度高;pts 时钟(音频 44100 vs 视频 90000)需对齐,否则 RTMP 客户端音画不同步。**缓解**:音频 pts 用采集系统时钟(ms)统一,RTSP/RTMP timestamp 按各自时钟换算。
- **R2(RTP 双 track 状态)**:`RtspServer` 现为单 video track,加 audio track 需在 `RtspClient` 维护两套 seq/ssrc/timestamp。**缓解**:参考现有 `sendNaluToClient` 结构对称实现。
- **R3(ArkTS bindSheet 兼容)**:依赖 ArkUI 版本。**缓解**:降级方案见 §6。
- **R4(无法本地编译)**:native 错误只能真机暴露。**缓解**:严格参照 `VideoEncoderEngine` 范式 + 充分 log。

## 9. 不在范围内(YAGNI)

- 多音轨/噪声消除/AGC/AEC 等音频增强;
- 视频编码器参数动态调整(保持现有推流中锁定);
- 「活动日志」「人体检测」区块改造(保留现状);
- 回放播放器(摄像机 tab)的静音逻辑(那是 `VideoStreamManager` 本地播放音量,与本机推流无关)。

## 10. 文件改动清单

**新增**:
- `surveillance/cams/src/main/cpp/audio_encoder_engine.h`
- `surveillance/cams/src/main/cpp/audio_encoder_engine.cpp`

**修改**:
- `surveillance/cams/src/main/cpp/napi_init.cpp`(注册 5 个音频导出)
- `surveillance/cams/src/main/cpp/types/rtspencoder/Index.d.ts`(音频类型 + 5 导出)
- `surveillance/cams/src/main/cpp/CMakeLists.txt`(源文件 + 2 个库)
- `surveillance/cams/src/main/ets/utils/RtspServer.ets`(SDP audio 段 + sendAacData + client audio track 状态)
- `surveillance/cams/src/main/ets/utils/RtmpPushManager.ets`(sendAacData + audio tag)
- `surveillance/cams/src/main/ets/utils/CameraStreamManager.ets`(音频生命周期 + setAudioMuted + 麦克风权限)
- `surveillance/cams/src/main/ets/components/NvrSecondaryScreens.ets`(#1 预览按钮、#2 静音接线、#4 设置 sheet、移除死开关)
- `surveillance/cams/src/main/ets/pages/MainPage.ets`(#3 全屏隐藏栏回调)
