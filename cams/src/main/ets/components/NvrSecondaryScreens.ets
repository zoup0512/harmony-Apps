import { RecordingFile, readableFileSize } from '../model/RecordingFile';
import { buildPhoneRtspAddress } from '../utils/NetworkUtils';
import { CameraStreamManager, StreamStatus, PersonEventLog } from '../utils/CameraStreamManager';
import { common } from '@kit.AbilityKit';

interface ThemeOptionItem {
  value: string;
  label: string;
}

interface SnapshotGroup {
  label: string;
  items: RecordingFile[];
}

function formatDateGroupLabel(timestamp: number, context: common.Context): string {
  const date = new Date(timestamp);
  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const yesterdayStart = new Date(todayStart.getTime() - 86400000);
  const dateStart = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  if (dateStart.getTime() === todayStart.getTime()) return context.resourceManager.getStringByNameSync('date_today');
  if (dateStart.getTime() === yesterdayStart.getTime()) return context.resourceManager.getStringByNameSync('date_yesterday');
  return context.resourceManager.getStringByNameSync('date_format_long').replace('%d', String(date.getFullYear())).replace('%d', String(date.getMonth() + 1)).replace('%d', String(date.getDate()));
}

function groupSnapshotsByDate(snapshots: RecordingFile[], context: common.Context): SnapshotGroup[] {
  const groups: SnapshotGroup[] = [];
  for (const s of snapshots) {
    const ts = s.startTime ?? 0;
    const label = ts > 0 ? formatDateGroupLabel(ts, context) : context.resourceManager.getStringByNameSync('date_unknown');
    let group = groups.find(g => g.label === label);
    if (!group) {
      group = { label, items: [] };
      groups.push(group);
    }
    group.items.push(s);
  }
  return groups;
}

@Component
export struct ActivityStreamScreen {
  recordings: RecordingFile[] = [];
  bgColor: string = '#F7F8FA';
  surfaceColor: string = '#FFFFFF';
  onSurfaceColor: string = '#1B1B1D';
  onSurfaceVariantColor: string = '#6B6F76';
  accentColor: string = '#20B486';
  onPrimaryColor: string = '#FFFFFF';
  surfaceVariantColor: string = '#F0F1F5';
  secondaryContainerColor: string = '#D6F3E8';
  errorColor: string = '#E53935';
  outlineVariantColor: string = '#E8E9ED';
  onOpenRecording: (file: RecordingFile) => void = () => {};
  onRefreshRecordings: () => void = () => {};
  rtmpUrlInput: string = '';
  rtmpStreamKeyInput: string = '';
  rtmpUsernameInput: string = '';
  rtmpPasswordInput: string = '';
  @State selectedStreamTool: string = 'rtsp';
  @State isStreaming: boolean = false;
  @State useFrontCamera: boolean = false;
  @State statusText: string = '';
  @State rtspAddress: string = buildPhoneRtspAddress();
  @State clientCount: number = 0;
  @State personDetectionEnabled: boolean = false;
  @State personDetected: boolean = false;
  @State personEvents: PersonEventLog[] = [];
  @StorageLink('isAppForeground') @Watch('onAppForegroundChange') isAppForeground: boolean = true;
  private streamManager: CameraStreamManager | null = null;
  private xComponentController: XComponentController = new XComponentController();
  private previewSurfaceId: string = '';

  buildRtmpUrl(): string {
    const host = this.rtmpUrlInput.replace(/^rtmp:\/\//i, '');
    return `rtmp://${host}/${this.rtmpStreamKeyInput}`;
  }

  streamTargetText(): Resource | string {
    if (this.selectedStreamTool === 'rtmp') {
      return this.rtmpUrlInput
        ? $r('app.string.stream_target', this.buildRtmpUrl())
        : $r('app.string.rtmp_target_not_configured');
    }
    return $r('app.string.stream_address', this.rtspAddress);
  }

  aboutToAppear(): void {
    this.rtspAddress = buildPhoneRtspAddress();
    const context = getContext(this) as common.Context;
    this.streamManager = new CameraStreamManager(context);
    this.streamManager.setStatusCallback((status: StreamStatus) => {
      this.isStreaming = status.isStreaming;
      this.statusText = status.statusText;
      this.clientCount = status.clientCount;
      this.personDetected = status.personDetected;
      this.personEvents = status.personEvents;
    });
    console.info(`ActivityStreamScreen aboutToAppear: isAppForeground=${this.isAppForeground}`);
  }

  aboutToDisappear(): void {
    if (this.streamManager) {
      this.streamManager.release();
      this.streamManager = null;
    }
  }

  onAppForegroundChange(): void {
    console.info(`ActivityStreamScreen onAppForegroundChange: isAppForeground=${this.isAppForeground}, isStreaming=${this.isStreaming}, streamManager=${this.streamManager !== null}`);
    if (!this.streamManager) {
      console.warn('ActivityStreamScreen onAppForegroundChange: streamManager is null, skip');
      return;
    }
    if (this.isAppForeground) {
      console.info('ActivityStreamScreen onAppForegroundChange: calling resumeStream()');
      this.streamManager.resumeStream();
    } else {
      console.info('ActivityStreamScreen onAppForegroundChange: calling pauseStream()');
      this.streamManager.pauseStream();
    }
  }

  private cameraDisplayName(recording: RecordingFile): string {
    return recording.cameraName && recording.cameraName.trim() !== ''
      ? recording.cameraName
      : getContext(this).resourceManager.getStringByNameSync('recording_unknown_camera');
  }

  private recordingMetaText(recording: RecordingFile): string {
    const timeStr = recording.startTime ? new Date(recording.startTime).toLocaleTimeString() : '';
    const sizeStr = readableFileSize(recording.fileSize);
    return timeStr ? `${timeStr} · ${sizeStr}` : sizeStr;
  }

  private personEventMetaText(evt: PersonEventLog): string {
    const template = getContext(this).resourceManager.getStringByNameSync('person_event_meta');
    return template.replace('%s', `${(evt.confidence * 100).toFixed(0)}%`).replace('%s', evt.bounds);
  }

  private activityCountText(): string {
    return getContext(this).resourceManager.getStringByNameSync('activity_log_count').replace('%d', String(this.recordings.length));
  }

  build(): void {
    Column() {
        Text($r('app.string.stream_mode_label'))
          .fontSize(12)
          .fontColor(this.onSurfaceVariantColor)
          .fontWeight(FontWeight.Medium)
          .width('100%')

        Row({ space: 4 }) {
          Text($r('app.string.rtsp_server'))
              .fontSize(14)
              .fontColor(this.selectedStreamTool === 'rtsp' ? this.onPrimaryColor : this.onSurfaceVariantColor)
              .fontWeight(this.selectedStreamTool === 'rtsp' ? FontWeight.Medium : FontWeight.Normal)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 9, bottom: 9 })
              .backgroundColor(this.selectedStreamTool === 'rtsp' ? this.accentColor : Color.Transparent)
              .borderRadius(10)
              .onClick(() => {
                this.selectedStreamTool = 'rtsp';
                if (this.streamManager) {
                  this.streamManager.setStreamMode('rtsp');
                }
              })

            Text($r('app.string.rtmp_stream'))
              .fontSize(14)
              .fontColor(this.selectedStreamTool === 'rtmp' ? this.onPrimaryColor : this.onSurfaceVariantColor)
              .fontWeight(this.selectedStreamTool === 'rtmp' ? FontWeight.Medium : FontWeight.Normal)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 9, bottom: 9 })
              .backgroundColor(this.selectedStreamTool === 'rtmp' ? this.accentColor : Color.Transparent)
              .borderRadius(10)
              .onClick(() => {
                this.selectedStreamTool = 'rtmp';
                if (this.streamManager) {
                  this.streamManager.setStreamMode('rtmp');
                  this.streamManager.setRtmpConfig(
                    this.rtmpUrlInput,
                    this.rtmpStreamKeyInput,
                    this.rtmpUsernameInput,
                    this.rtmpPasswordInput,
                  );
                }
              })
          }
          .width('100%')
          .padding(3)
          .backgroundColor(this.surfaceVariantColor)
          .borderRadius(13)
          .margin({ top: 8 })

          // Phone camera streaming card
          Column() {
            Row() {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.video_fill'))
                  .fontSize(17)
                  .fontColor([this.accentColor])
                Text(this.selectedStreamTool === 'rtmp' ? $r('app.string.rtmp_stream_to_server') : $r('app.string.phone_rtsp_stream'))
                  .fontSize(16)
                  .fontColor(this.onSurfaceColor)
                  .fontWeight(FontWeight.Bold)
              }
              .layoutWeight(1)

              Row({ space: 5 }) {
                Circle({ width: 6, height: 6 })
                  .fill(this.isStreaming ? this.onPrimaryColor : this.onSurfaceVariantColor)
                Text(this.isStreaming ? $r('app.string.status_running') : $r('app.string.status_standby_btn'))
                  .fontSize(12)
                  .fontColor(this.isStreaming ? this.onPrimaryColor : this.onSurfaceVariantColor)
                  .fontWeight(FontWeight.Medium)
              }
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor(this.isStreaming ? this.accentColor : this.surfaceVariantColor)
                .borderRadius(999)
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)

            Text(this.statusText)
              .fontSize(12)
              .fontColor(this.onSurfaceVariantColor)
              .margin({ top: 8 })
              .width('100%')

            Text($r('app.string.phone_camera_hint'))
              .fontSize(12)
              .fontColor(this.onSurfaceVariantColor)
              .margin({ top: 4 })
              .width('100%')

            Stack({ alignContent: Alignment.TopStart }) {
              XComponent({
                id: 'rtspCameraPreview',
                type: XComponentType.SURFACE,
                controller: this.xComponentController
              })
                .onLoad(() => {
                  this.previewSurfaceId = this.xComponentController.getXComponentSurfaceId();
                  console.info(`ActivityStreamScreen XComponent.onLoad: surfaceId=${this.previewSurfaceId}, hasStreamManager=${this.streamManager !== null}`);
                  if (this.streamManager && this.previewSurfaceId) {
                    this.streamManager.initPreview(this.previewSurfaceId).then(() => {
                      console.info(`ActivityStreamScreen XComponent.onLoad: initPreview completed`);
                    }).catch((e: Error) => {
                      console.error(`ActivityStreamScreen XComponent.onLoad: initPreview failed: ${e.message}`);
                    });
                  } else {
                    console.error(`ActivityStreamScreen XComponent.onLoad: streamManager=${this.streamManager !== null}, surfaceId='${this.previewSurfaceId}'`);
                  }
                })
                .width('100%')
                .height('100%')

              if (!this.isStreaming && this.statusText === '') {
                Text($r('app.string.preview_area'))
                  .fontSize(16)
                  .fontColor('#FFFFFF80')
              }

              if (this.isStreaming) {
                Row({ space: 5 }) {
                  Circle({ width: 6, height: 6 })
                    .fill(this.errorColor)
                  Text($r('app.string.status_live'))
                    .fontSize(11)
                    .fontColor('#FFFFFF')
                    .fontWeight(FontWeight.Bold)
                }
                .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                .backgroundColor('#00000080')
                .borderRadius(999)
                .margin(10)
              }
            }
            .width('100%')
            .aspectRatio(4 / 3)
            .borderRadius(16)
            .backgroundColor('#000000')
            .margin({ top: 12 })
            .clip(true)

            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.link'))
                .fontSize(14)
                .fontColor([this.onSurfaceVariantColor])
              Text(this.streamTargetText())
                .fontSize(12)
                .fontColor(this.onSurfaceVariantColor)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .margin({ top: 12 })

            if (this.selectedStreamTool === 'rtsp') {
              Column() {
                Column() {
                  QRCode(this.rtspAddress)
                    .width(150)
                    .height(150)
                }
                .padding(10)
                .backgroundColor('#FFFFFF')
                .borderRadius(12)

                Text($r('app.string.scan_to_connect'))
                  .fontSize(12)
                  .fontColor(this.onSurfaceVariantColor)
                  .margin({ top: 10 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding(16)
              .margin({ top: 12 })
              .backgroundColor(this.surfaceVariantColor)
              .borderRadius(16)
            }

            Row({ space: 10 }) {
              Button(this.useFrontCamera ? $r('app.string.switch_to_back') : $r('app.string.switch_to_front'))
                .layoutWeight(1)
                .height(46)
                .fontColor(this.onSurfaceColor)
                .backgroundColor(this.surfaceVariantColor)
                .borderRadius(12)
                .onClick(() => {
                  if (this.streamManager) {
                    console.info(`ActivityStreamScreen switchCamera onClick: BEFORE ui_useFrontCamera=${this.useFrontCamera}, mgr_useFrontCamera=${this.streamManager.isFrontCamera()}`);
                    this.streamManager.switchCamera().then(() => {
                      const mgrFront = this.streamManager!.isFrontCamera();
                      console.info(`ActivityStreamScreen switchCamera then: mgr_useFrontCamera=${mgrFront}, old ui_useFrontCamera=${this.useFrontCamera}`);
                      this.useFrontCamera = mgrFront;
                      console.info(`ActivityStreamScreen switchCamera then: AFTER ui_useFrontCamera=${this.useFrontCamera}`);
                    }).catch((e: Error) => {
                      console.error(`ActivityStreamScreen switchCamera failed: ${e.message}`);
                      const mgrFront = this.streamManager!.isFrontCamera();
                      console.info(`ActivityStreamScreen switchCamera catch: reverting ui to mgr_useFrontCamera=${mgrFront}`);
                      this.useFrontCamera = mgrFront;
                    });
                  } else {
                    console.warn('ActivityStreamScreen switchCamera onClick: streamManager is null');
                  }
                })
              Button(this.isStreaming ? $r('app.string.stop_stream') : $r('app.string.start_stream'))
                .layoutWeight(1)
                .height(46)
                .fontColor(this.onPrimaryColor)
                .backgroundColor(this.isStreaming ? this.errorColor : this.accentColor)
                .borderRadius(12)
                .onClick(() => {
                  if (this.isStreaming) {
                    this.streamManager?.stopStream();
                  } else {
                    if (this.selectedStreamTool === 'rtmp' && this.streamManager) {
                      this.streamManager.setStreamMode('rtmp');
                      this.streamManager.setRtmpConfig(
                        this.rtmpUrlInput,
                        this.rtmpStreamKeyInput,
                        this.rtmpUsernameInput,
                        this.rtmpPasswordInput,
                      );
                    }
                    this.streamManager?.startStream();
                  }
                })
            }
            .width('100%')
            .margin({ top: 12 })
          }
          .width('100%')
          .borderRadius(20)
          .backgroundColor(this.surfaceColor)
          .padding(16)
          .margin({ top: 14 })

          Column() {
            Row() {
              Text($r('app.string.person_detection'))
                .fontSize(16)
                .fontColor(this.onSurfaceColor)
                .fontWeight(FontWeight.Medium)
                .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.personDetectionEnabled })
                .onChange((on: boolean) => {
                  this.personDetectionEnabled = on;
                  this.streamManager?.setPersonDetectionEnabled(on);
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)

            if (this.personDetectionEnabled) {
              Divider().color(this.outlineVariantColor).margin({ top: 12, bottom: 12 })
              Row({ space: 6 }) {
                Circle({ width: 8, height: 8 })
                  .fill(this.personDetected ? this.errorColor : this.onSurfaceVariantColor)
                Text(this.personDetected ? $r('app.string.person_detected') : $r('app.string.person_detection_idle'))
                  .fontSize(13)
                  .fontColor(this.personDetected ? this.errorColor : this.onSurfaceVariantColor)
                  .fontWeight(FontWeight.Medium)
              }
              .width('100%')
            }
          }
          .width('100%')
          .borderRadius(20)
          .backgroundColor(this.surfaceColor)
          .padding(16)
          .margin({ top: 14 })

          if (this.personDetectionEnabled) {
            Row() {
              Text($r('app.string.person_event_log'))
                .fontSize(16)
                .fontColor(this.onSurfaceVariantColor)
                .fontWeight(FontWeight.Medium)
                .layoutWeight(1)
              if (this.personEvents.length > 0) {
                Text(String(this.personEvents.length))
                  .fontSize(12)
                  .fontColor(this.onSurfaceVariantColor)
              }
            }
            .width('100%')
            .margin({ top: 14, bottom: 4 })

            if (this.personEvents.length === 0) {
              Text($r('app.string.person_no_events'))
                .fontSize(14)
                .fontColor(this.onSurfaceVariantColor)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(24)
            } else {
              ForEach(this.personEvents, (evt: PersonEventLog) => {
                Row() {
                  Circle({ width: 8, height: 8 })
                    .fill(this.errorColor)
                    .margin({ right: 12 })

                  Column() {
                    Text(new Date(evt.timestamp).toLocaleTimeString())
                      .fontSize(14)
                      .fontColor(this.onSurfaceColor)
                      .fontWeight(FontWeight.Medium)
                    Text(this.personEventMetaText(evt))
                      .fontSize(12)
                      .fontColor(this.onSurfaceVariantColor)
                      .margin({ top: 2 })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .borderRadius(14)
                .backgroundColor(this.surfaceColor)
                .padding(14)
                .margin({ top: 8 })
              }, (evt: PersonEventLog) => evt.timestamp.toString())
            }
          }

          Row() {
            Text($r('app.string.activity_log'))
              .fontSize(16)
              .fontColor(this.onSurfaceVariantColor)
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1)

            if (this.recordings.length > 0) {
              Text(this.activityCountText())
                .fontSize(12)
                .fontColor(this.onSurfaceVariantColor)
                .margin({ right: 12 })
            }

            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(18)
              .fontColor([this.accentColor])
              .onClick(() => this.onRefreshRecordings())
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: 14, bottom: 4 })

          if (this.recordings.length === 0) {
            Column() {
              Stack() {
                Circle({ width: 88, height: 88 })
                  .fill(this.secondaryContainerColor)
                SymbolGlyph($r('sys.symbol.histogram'))
                  .fontSize(36)
                  .fontColor([this.accentColor])
              }
              .width(88)
              .height(88)

              Text($r('app.string.no_activity'))
                .fontSize(16)
                .fontColor(this.onSurfaceColor)
                .fontWeight(FontWeight.Medium)
                .margin({ top: 16 })
              Text($r('app.string.no_activity_hint'))
                .fontSize(13)
                .fontColor(this.onSurfaceVariantColor)
                .textAlign(TextAlign.Center)
                .margin({ top: 6 })
            }
            .width('100%')
            .padding({ top: 28, bottom: 28 })
            .alignItems(HorizontalAlign.Center)
          } else {
            ForEach(groupSnapshotsByDate(this.recordings, getContext(this)), (group: SnapshotGroup) => {
              Text(group.label)
                .fontSize(14)
                .fontColor(this.onSurfaceVariantColor)
                .fontWeight(FontWeight.Medium)
                .width('100%')
                .margin({ top: 12 })

              ForEach(group.items, (recording: RecordingFile) => {
                Row() {
                  Stack() {
                    Circle({ width: 44, height: 44 })
                      .fill(this.secondaryContainerColor)
                    SymbolGlyph($r('sys.symbol.video_fill'))
                      .fontSize(18)
                      .fontColor([this.accentColor])
                  }
                  .width(44)
                  .height(44)
                  .margin({ right: 12 })

                  Column() {
                    Text(this.cameraDisplayName(recording))
                      .fontSize(15)
                      .fontColor(this.onSurfaceColor)
                      .fontWeight(FontWeight.Medium)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.recordingMetaText(recording))
                      .fontSize(12)
                      .fontColor(this.onSurfaceVariantColor)
                      .margin({ top: 3 })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(18)
                    .fontColor([this.onSurfaceVariantColor])
                }
                .width('100%')
                .borderRadius(16)
                .backgroundColor(this.surfaceColor)
                .padding(12)
                .margin({ top: 8 })
                .onClick(() => this.onOpenRecording(recording))
              }, (recording: RecordingFile) => recording.filePath)
            }, (group: SnapshotGroup) => `${group.label}_${group.items.map(i => i.filePath).join(',')}`)
          }
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 12, bottom: 100 })
        .backgroundColor(this.bgColor)
    }
  }

@Component
export struct SnapshotScreen {
  @Prop snapshots: RecordingFile[] = [];
  bgColor: string = '#F7F8FA';
  surfaceColor: string = '#FFFFFF';
  onSurfaceColor: string = '#1B1B1D';
  onSurfaceVariantColor: string = '#6B6F76';
  accentColor: string = '#20B486';
  onPrimaryColor: string = '#FFFFFF';
  onOpenSnapshot: (file: RecordingFile) => void = () => {};
  onDeleteSnapshot: (file: RecordingFile) => void = () => {};
  onShareSnapshot: (file: RecordingFile) => void = () => {};
  onViewMore: () => void = () => {};

  build(): void {
    Scroll() {
      Column() {
        if (this.snapshots.length === 0) {
          Column() {
            Stack() {
              Circle({ width: 180, height: 180 })
                .fill('#1A3A3A')

              Column() {
                Row() {
                  Column()
                    .width(52)
                    .height(40)
                    .borderRadius(6)
                    .border({ width: 2, color: '#6B8A7A' })
                    .backgroundColor(Color.Transparent)
                    .position({ x: 0, y: 8 })

                  Column()
                    .width(52)
                    .height(40)
                    .borderRadius(6)
                    .border({ width: 2, color: this.accentColor })
                    .backgroundColor(Color.Transparent)
                    .position({ x: 16, y: 0 })
                }
                .width(68)
                .height(48)

                Row() {
                  Circle({ width: 8, height: 8 })
                    .fill(this.accentColor)
                    .margin({ right: 6 })

                  Column()
                    .width(16)
                    .height(10)
                    .backgroundColor(this.accentColor)
                    .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: 5, bottomRight: 5 })
                }
                .margin({ top: -2 })
              }
            }
            .width(180)
            .height(180)

            Text($r('app.string.tab_snapshots'))
              .fontSize(24)
              .fontColor(this.onSurfaceColor)
              .fontWeight(FontWeight.Bold)
              .margin({ top: 28 })

            Text($r('app.string.no_snapshots_hint'))
              .fontSize(14)
              .fontColor(this.onSurfaceVariantColor)
              .textAlign(TextAlign.Center)
              .margin({ top: 10, left: 32, right: 32 })

            Text($r('app.string.no_snapshots_action'))
              .fontSize(16)
              .fontColor(this.onPrimaryColor)
              .fontWeight(FontWeight.Bold)
              .textAlign(TextAlign.Center)
              .padding({ left: 40, right: 40, top: 14, bottom: 14 })
              .backgroundColor(this.accentColor)
              .borderRadius(26)
              .margin({ top: 36 })
              .width('80%')
              .onClick(() => this.onViewMore())
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
        ForEach(groupSnapshotsByDate(this.snapshots, getContext(this)), (group: SnapshotGroup) => {
          Text(group.label)
            .fontSize(16)
            .fontColor(this.onSurfaceColor)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .margin({ top: 16, bottom: 8 })

          ForEach(group.items, (snapshot: RecordingFile) => {
            Stack({ alignContent: Alignment.BottomEnd }) {
              Image(`file://${snapshot.filePath}`)
                .width('100%')
                .aspectRatio(16 / 9)
                .borderRadius(14)
                .objectFit(ImageFit.Cover)
                .backgroundColor(this.surfaceColor)
                .onError((err) => {
                  console.error(`SnapshotScreen Image onError: filePath='${snapshot.filePath}'`);
                })
                .onComplete(() => {
                  console.info(`SnapshotScreen Image onComplete: filePath='${snapshot.filePath}'`);
                })

              Row() {
                SymbolGlyph($r('sys.symbol.share'))
                  .fontSize(18)
                  .fontColor(['#FFFFFF'])
                  .margin({ right: 12 })
                  .onClick(() => this.onShareSnapshot(snapshot))
                SymbolGlyph($r('sys.symbol.trash_fill'))
                  .fontSize(18)
                  .fontColor(['#FFFFFF'])
                  .onClick(() => this.onDeleteSnapshot(snapshot))
              }
              .padding({ right: 12, bottom: 10 })
            }
            .width('100%')
            .borderRadius(14)
            .margin({ bottom: 12 })
            .onClick(() => this.onOpenSnapshot(snapshot))
            .gesture(
              LongPressGesture()
                .onAction(() => this.onDeleteSnapshot(snapshot))
            )
          }, (snapshot: RecordingFile) => snapshot.filePath)
        }, (group: SnapshotGroup) => `${group.label}_${group.items.map(i => i.filePath).join(',')}`)
        }
      }
      .width('100%')
      .padding({ left: 16, top: 12, right: 16, bottom: 100 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor)
  }
}

@Component
export struct SettingsHomeScreen {
  storagePathInput: string = '';
  recordingQualityInput: string = '1080p';
  recordingDurationInput: string = '30';
  appearanceThemeMode: string = 'light';
  rtmpUrlInput: string = '';
  rtmpStreamKeyInput: string = '';
  rtmpUsernameInput: string = '';
  rtmpPasswordInput: string = '';
  rtmpAudioEnabled: boolean = true;
  rtmpAutoStreamEnabled: boolean = false;
  @Prop bgColor: string = '#F7F8FA';
  @Prop surfaceColor: string = '#FFFFFF';
  @Prop surfaceVariantColor: string = '#F0F1F5';
  @Prop onSurfaceColor: string = '#1B1B1D';
  @Prop onSurfaceVariantColor: string = '#6B6F76';
  @Prop accentColor: string = '#20B486';
  @Prop onPrimaryColor: string = '#FFFFFF';
  @Prop outlineVariantColor: string = '#E0E2E8';
  onStoragePathChange: (v: string) => void = () => {};
  onRecordingQualityChange: (v: string) => void = () => {};
  onRecordingDurationChange: (v: string) => void = () => {};
  onThemeModeChange: (v: string) => void = () => {};
  onRtmpUrlChange: (v: string) => void = () => {};
  onRtmpStreamKeyChange: (v: string) => void = () => {};
  onRtmpUsernameChange: (v: string) => void = () => {};
  onRtmpPasswordChange: (v: string) => void = () => {};
  onRtmpAudioEnabledChange: (v: boolean) => void = () => {};
  onRtmpAutoStreamChange: (v: boolean) => void = () => {};
  onClearRecordings: () => void = () => {};
  onManageRtmpSettings: () => void = () => {};
  @State showPassword: boolean = false;
  @Prop bgPlaybackEnabled: boolean = false;
  onBgPlaybackChange: (enabled: boolean) => void = () => {};
  appLockEnabled: boolean = false;
  onAppLockChange: (enabled: boolean) => void = () => {};
  onSelectStoragePath: () => void = () => {};

  build(): void {
    Column() {
        // Appearance
        Text($r('app.string.section_appearance'))
          .fontSize(16)
          .fontColor(this.onSurfaceVariantColor)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 16, bottom: 10 })

        // Theme selector
        Row() {
          Text($r('app.string.settings_theme'))
            .fontSize(16)
            .fontColor(this.onSurfaceColor)
            .fontWeight(FontWeight.Bold)
            .width(46)

          Row({ space: 3 }) {
            ForEach([
              { value: 'system', label: getContext(this).resourceManager.getStringByNameSync('theme_system') },
              { value: 'light', label: getContext(this).resourceManager.getStringByNameSync('theme_light') },
              { value: 'dark', label: getContext(this).resourceManager.getStringByNameSync('theme_dark') },
            ], (item: ThemeOptionItem) => {
              Text(item.label)
                .fontSize(14)
                .fontColor(this.onSurfaceColor)
                .fontWeight(this.appearanceThemeMode === item.value ? FontWeight.Bold : FontWeight.Medium)
                .layoutWeight(1)
                .height(34)
                .textAlign(TextAlign.Center)
                .backgroundColor(this.appearanceThemeMode === item.value ? this.surfaceColor : Color.Transparent)
                .borderRadius(10)
                .onClick(() => this.onThemeModeChange(item.value))
            })
          }
          .layoutWeight(1)
          .backgroundColor(this.surfaceVariantColor)
          .borderRadius(12)
          .padding({ left: 2, right: 2, top: 2, bottom: 2 })
        }
        .width('100%')
        .borderRadius(24)
        .backgroundColor(this.surfaceColor)
        .padding({ left: 18, right: 18, top: 16, bottom: 16 })

        // Device options
        Text($r('app.string.section_device_options'))
          .fontSize(16)
          .fontColor(this.onSurfaceVariantColor)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 16, bottom: 10 })

        Column() {
          // Storage path
          Column() {
            Text($r('app.string.settings_storage_path'))
              .fontSize(14)
              .fontColor(this.onSurfaceColor)
              .fontWeight(FontWeight.Medium)
              .width('100%')
              .textAlign(TextAlign.Start)
            Row() {
              Text(this.storagePathInput || $r('app.string.storage_path_hint'))
                .fontSize(14)
                .fontColor(this.storagePathInput ? this.onSurfaceColor : this.onSurfaceVariantColor)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text($r('app.string.action_select'))
                .fontSize(12)
                .fontColor(this.accentColor)
                .fontWeight(FontWeight.Medium)
            }
            .width('100%')
            .borderRadius(12)
            .border({ width: 1, color: this.outlineVariantColor })
            .backgroundColor(this.surfaceVariantColor)
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })
            .margin({ top: 6 })
            .onClick(() => this.onSelectStoragePath())
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })

          Divider().color(this.outlineVariantColor).margin({ left: 16, right: 16 })

          // Recording quality
          Column() {
            Text($r('app.string.settings_recording_quality'))
              .fontSize(14)
              .fontColor(this.onSurfaceColor)
              .fontWeight(FontWeight.Medium)
              .width('100%')
              .textAlign(TextAlign.Start)
            Row({ space: 8 }) {
              ForEach(['4K', '1080p', '720p', '480p'], (option: string) => {
                Text(option)
                  .fontSize(14)
                  .fontColor(this.recordingQualityInput === option ? this.onPrimaryColor : this.onSurfaceVariantColor)
                  .fontWeight(this.recordingQualityInput === option ? FontWeight.Medium : FontWeight.Normal)
                  .layoutWeight(1)
                  .textAlign(TextAlign.Center)
                  .padding({ top: 8, bottom: 8 })
                  .backgroundColor(this.recordingQualityInput === option ? this.accentColor : this.surfaceVariantColor)
                  .borderRadius(20)
                  .onClick(() => this.onRecordingQualityChange(option))
              })
            }
            .width('100%')
            .margin({ top: 8 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })

          Divider().color(this.outlineVariantColor).margin({ left: 16, right: 16 })

          // Recording duration
          Column() {
            Text($r('app.string.settings_recording_duration'))
              .fontSize(14)
              .fontColor(this.onSurfaceColor)
              .fontWeight(FontWeight.Medium)
              .width('100%')
              .textAlign(TextAlign.Start)
            TextInput({ text: this.recordingDurationInput, placeholder: $r('app.string.duration_hint') })
              .fontSize(14)
              .fontColor(this.onSurfaceColor)
              .backgroundColor(Color.Transparent)
              .type(InputType.Number)
              .width('100%')
              .margin({ top: 6 })
              .onChange((v: string) => this.onRecordingDurationChange(v))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        }
        .width('100%')
        .borderRadius(20)
        .backgroundColor(this.surfaceColor)

        // Background playback toggle
        Row() {
          Column() {
            Text($r('app.string.settings_bg_playback'))
              .fontSize(16)
              .fontColor(this.onSurfaceColor)
              .fontWeight(FontWeight.Medium)
            Text($r('app.string.settings_bg_playback_desc'))
              .fontSize(12)
              .fontColor(this.onSurfaceVariantColor)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.bgPlaybackEnabled })
            .onChange((v: boolean) => { this.onBgPlaybackChange(v); })
        }
        .width('100%')
        .borderRadius(20)
        .backgroundColor(this.surfaceColor)
        .padding(16)
        .margin({ top: 10 })

        // RTMP
        Text($r('app.string.section_rtmp'))
          .fontSize(16)
          .fontColor(this.onSurfaceVariantColor)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 16, bottom: 10 })

        Column() {
          this.SettingsTextField($r('app.string.rtmp_server_addr'), $r('app.string.rtmp_server_hint'), this.rtmpUrlInput, this.onRtmpUrlChange, false)
          Divider().color(this.outlineVariantColor).margin({ left: 16, right: 16 })
          this.SettingsTextField($r('app.string.rtmp_stream_key'), $r('app.string.rtmp_stream_key_hint'), this.rtmpStreamKeyInput, this.onRtmpStreamKeyChange, false)
          Divider().color(this.outlineVariantColor).margin({ left: 16, right: 16 })
          this.SettingsTextField($r('app.string.rtmp_auth_username'), $r('app.string.field_optional'), this.rtmpUsernameInput, this.onRtmpUsernameChange, false)
          Divider().color(this.outlineVariantColor).margin({ left: 16, right: 16 })
          this.SettingsTextField($r('app.string.rtmp_auth_password'), $r('app.string.field_optional'), this.rtmpPasswordInput, this.onRtmpPasswordChange, !this.showPassword)
        }
        .width('100%')
        .borderRadius(20)
        .backgroundColor(this.surfaceColor)

        // Audio toggle
        Row() {
          Column() {
            Text($r('app.string.settings_mic_audio'))
              .fontSize(16)
              .fontColor(this.onSurfaceColor)
              .fontWeight(FontWeight.Medium)
            Text($r('app.string.settings_mic_audio_desc'))
              .fontSize(12)
              .fontColor(this.onSurfaceVariantColor)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.rtmpAudioEnabled })
            .onChange((v: boolean) => this.onRtmpAudioEnabledChange(v))
        }
        .width('100%')
        .borderRadius(20)
        .backgroundColor(this.surfaceColor)
        .padding(16)
        .margin({ top: 10 })

        // Auto stream toggle
        Row() {
          Column() {
            Text($r('app.string.settings_ask_rtmp'))
              .fontSize(16)
              .fontColor(this.onSurfaceColor)
              .fontWeight(FontWeight.Medium)
            Text($r('app.string.settings_ask_rtmp_desc'))
              .fontSize(12)
              .fontColor(this.onSurfaceVariantColor)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.rtmpAutoStreamEnabled })
            .onChange((v: boolean) => this.onRtmpAutoStreamChange(v))
        }
        .width('100%')
        .borderRadius(20)
        .backgroundColor(this.surfaceColor)
        .padding(16)
        .margin({ top: 10 })

        // App lock toggle
        Row() {
          Column() {
            Text($r('app.string.settings_app_lock'))
              .fontSize(16)
              .fontColor(this.onSurfaceColor)
              .fontWeight(FontWeight.Medium)
            Text($r('app.string.settings_app_lock_desc'))
              .fontSize(12)
              .fontColor(this.onSurfaceVariantColor)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.appLockEnabled })
            .onChange((v: boolean) => this.onAppLockChange(v))
        }
        .width('100%')
        .borderRadius(20)
        .backgroundColor(this.surfaceColor)
        .padding(16)
        .margin({ top: 10 })

        // RTMP settings manager
        Column() {
          Text($r('app.string.rtmp_settings_manager'))
            .fontSize(16)
            .fontColor(this.onSurfaceColor)
            .fontWeight(FontWeight.Medium)
          Text($r('app.string.rtmp_settings_manager_desc'))
            .fontSize(14)
            .fontColor(this.onSurfaceVariantColor)
            .margin({ top: 4 })
        }
        .width('100%')
        .borderRadius(18)
        .backgroundColor(this.surfaceColor)
        .padding(16)
        .margin({ top: 10 })
        .onClick(() => this.onManageRtmpSettings())

        // Clear recordings
        Text($r('app.string.clear_recordings'))
          .fontSize(16)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 16, bottom: 16 })
          .backgroundColor('#FF0000')
          .borderRadius(16)
          .margin({ top: 16 })
          .onClick(() => this.onClearRecordings())
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 120 })
      .backgroundColor(this.bgColor)
  }

  @Builder
  SettingsTextField(label: Resource, hint: Resource, value: string, onChange: (v: string) => void, password: boolean) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontColor(this.onSurfaceColor)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .textAlign(TextAlign.Start)
      if (password) {
        TextInput({ text: value, placeholder: hint })
          .fontSize(14)
          .fontColor(this.onSurfaceColor)
          .type(InputType.Password)
          .backgroundColor(Color.Transparent)
          .width('100%')
          .margin({ top: 6 })
          .onChange((v: string) => onChange(v))
      } else {
        TextInput({ text: value, placeholder: hint })
          .fontSize(14)
          .fontColor(this.onSurfaceColor)
          .backgroundColor(Color.Transparent)
          .width('100%')
          .margin({ top: 6 })
          .onChange((v: string) => onChange(v))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }
}
