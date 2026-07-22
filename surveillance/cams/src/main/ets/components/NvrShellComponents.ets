import { CameraDevice } from '../model/CameraDevice';
import { RecordingFile, readableFileSize } from '../model/RecordingFile';
import { promptAction } from '@kit.ArkUI';
import { PlaybackStreamType, playbackStreamTypeFromUrl } from '../utils/PlaybackModels';

const XCOMPONENT_TYPE_SURFACE = 0;

interface FilterChipItem {
  label: string;
  value: string;
}

interface TabBarItem {
  label: string;
  icon: Resource;
  index: number;
}

@Component
export struct NvrMainTopBar {
  @Prop selectedTab: number = 0;
  @Prop accentColor: string = '#20B486';
  @Prop bgColor: string = '#F7F8FA';
  @Prop onBackgroundColor: string = '#1B1B1D';
  @Prop onPrimaryColor: string = '#FFFFFF';
  onEditClick: () => void = () => {};
  onMenuClick: () => void = () => {};
  onAddClick: () => void = () => {};

  build(): void {
    Column() {
      Row() {
        Text(this.selectedTab === 0 ? $r('app.string.action_edit') : '')
          .fontSize(16)
          .fontColor(this.accentColor)
          .fontWeight(FontWeight.Medium)
          .onClick(() => this.onEditClick())
          .enabled(this.selectedTab === 0)

        Row({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.line_3_horizontal'))
            .fontSize(22)
            .fontColor([this.accentColor])
            .onClick(() => this.onMenuClick())

          Stack() {
            Circle({ width: 30, height: 30 })
              .fill(this.accentColor)
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(18)
              .fontColor([this.onPrimaryColor])
              .fontWeight(FontWeight.Bold)
          }
          .width(30)
          .height(30)
          .onClick(() => this.onAddClick())
        }
        .justifyContent(FlexAlign.End)
        .layoutWeight(1)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 18, right: 18, top: 10, bottom: 10 })

      Text(this.getTabTitle())
        .fontSize(28)
        .fontColor(this.onBackgroundColor)
        .fontWeight(FontWeight.Bold)
        .padding({ left: 18, bottom: 10 })
    }
    .width('100%')
    .backgroundColor(this.bgColor)
  }

  private getTabTitle(): string {
    switch (this.selectedTab) {
      case 0: return getContext(this).resourceManager.getStringByNameSync('tab_cameras');
      case 1: return getContext(this).resourceManager.getStringByNameSync('tab_dashboard');
      case 2: return getContext(this).resourceManager.getStringByNameSync('tab_activity');
      case 3: return getContext(this).resourceManager.getStringByNameSync('tab_snapshots');
      default: return getContext(this).resourceManager.getStringByNameSync('tab_settings');
    }
  }
}

@Component
export struct CameraHomeScreen {
  @Prop cameras: CameraDevice[] = [];
  @Prop snapshots: RecordingFile[] = [];
  @Prop selectedCameraId: string = '';
  @Prop playingCameraId: string = '';
  @Prop accentColor: string = '#20B486';
  @Prop bgColor: string = '#F7F8FA';
  @Prop surfaceColor: string = '#FFFFFF';
  @Prop surfaceVariantColor: string = '#F0F1F5';
  @Prop onBackgroundColor: string = '#1B1B1D';
  @Prop onSurfaceVariantColor: string = '#6B6F76';
  @Prop onPrimaryColor: string = '#FFFFFF';
  @Prop secondaryContainerColor: string = '#D6F3E8';
  @Prop errorColor: string = '#E53935';
  @Prop searchQuery: string = '';
  @Prop cameraFilter: string = 'all';
  onCameraClick: (device: CameraDevice) => void = () => {};
  onCameraLongPress: (device: CameraDevice) => void = () => {};
  onAddCamera: () => void = () => {};
  onSearchChange: (query: string) => void = () => {};
  onFilterChange: (filter: string) => void = () => {};
  @Prop gridColumns: number = 1;
  onGridColumnsChange: (cols: number) => void = () => {};

  build(): void {
    if (this.cameras.length === 0) {
      Column() {
        Stack() {
          Circle({ width: 72, height: 72 })
            .fill(this.surfaceVariantColor)
          SymbolGlyph($r('sys.symbol.camera_fill'))
            .fontSize(32)
            .fontColor([this.accentColor])
        }
        .width(72)
        .height(72)

        Text($r('app.string.no_cameras'))
          .fontSize(22)
          .fontColor(this.onBackgroundColor)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 16 })

        Text($r('app.string.no_cameras_hint'))
          .fontSize(14)
          .fontColor(this.onSurfaceVariantColor)
          .margin({ top: 6 })

        Text($r('app.string.add_camera'))
          .fontSize(16)
          .fontColor(this.onPrimaryColor)
          .fontWeight(FontWeight.Bold)
          .padding({ left: 22, right: 22, top: 12, bottom: 12 })
          .backgroundColor(this.accentColor)
          .borderRadius(18)
          .margin({ top: 24 })
          .onClick(() => this.onAddCamera())
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 20, right: 20 })
      .backgroundColor(this.bgColor)
    } else {
      Column() {
        // Search bar
        Row() {
          TextInput({ text: this.searchQuery, placeholder: $r('app.string.search_cameras') })
            .fontSize(14)
            .fontColor(this.onBackgroundColor)
            .backgroundColor(this.surfaceVariantColor)
            .borderRadius(12)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .layoutWeight(1)
            .onChange((v: string) => this.onSearchChange(v))

          if (this.searchQuery !== '') {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(16)
              .fontColor([this.onSurfaceVariantColor])
              .margin({ left: 8 })
              .onClick(() => this.onSearchChange(''))
          }
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 4, bottom: 8 })

        // Filter chips
        Row() {
          ForEach([
            { label: getContext(this).resourceManager.getStringByNameSync('filter_all'), value: 'all' },
            { label: getContext(this).resourceManager.getStringByNameSync('filter_online'), value: 'online' },
            { label: getContext(this).resourceManager.getStringByNameSync('filter_offline'), value: 'offline' },
          ], (item: FilterChipItem) => {
            Text(item.label)
              .fontSize(12)
              .fontColor(this.cameraFilter === item.value ? this.onPrimaryColor : this.onSurfaceVariantColor)
              .fontWeight(this.cameraFilter === item.value ? FontWeight.Medium : FontWeight.Normal)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .backgroundColor(this.cameraFilter === item.value ? this.accentColor : this.surfaceVariantColor)
              .borderRadius(999)
              .margin({ right: 8 })
              .onClick(() => this.onFilterChange(item.value))
          })
        }
        .width('100%')
        .padding({ left: 18, right: 18, bottom: 8 })

        Row() {
          Text($r('app.string.online_count', this.cameras.filter(c => c.isConnected).length, this.cameras.length))
            .fontSize(14)
            .fontColor(this.onSurfaceVariantColor)
            .fontWeight(FontWeight.Medium)

          Row({ space: 2 }) {
            ForEach([1, 2, 3], (cols: number) => {
              Text(cols === 1 ? '▢' : cols === 2 ? '⊞' : '⊟')
                .fontSize(14)
                .fontColor(this.gridColumns === cols ? this.onBackgroundColor : this.onSurfaceVariantColor)
                .fontWeight(FontWeight.Bold)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor(this.gridColumns === cols ? this.secondaryContainerColor : Color.Transparent)
                .borderRadius(999)
                .onClick(() => { this.onGridColumnsChange(cols); })
            })
          }
          .backgroundColor(this.surfaceVariantColor)
          .borderRadius(999)
          .padding(2)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 18, right: 16, top: 4, bottom: 10 })

        Grid() {
          ForEach(this.cameras, (device: CameraDevice) => {
            GridItem() {
              CameraGridCard({
                camera: device,
                isSelected: this.selectedCameraId === device.id,
                isPlaying: this.playingCameraId === device.id,
                accentColor: this.accentColor,
                surfaceColor: this.surfaceColor,
                surfaceVariantColor: this.surfaceVariantColor,
                onBackgroundColor: this.onBackgroundColor,
                onSurfaceVariantColor: this.onSurfaceVariantColor,
                secondaryContainerColor: this.secondaryContainerColor,
                errorColor: this.errorColor,
                onCardClick: () => this.onCameraClick(device),
                onLongPress: () => this.onCameraLongPress(device),
              })
            }
          }, (device: CameraDevice) => `${device.id}_${device.isConnected}_${device.isRecording}`)
        }
        .columnsTemplate(this.gridColumns === 1 ? '1fr' : this.gridColumns === 2 ? '1fr 1fr' : '1fr 1fr 1fr')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
        .columnsGap(12)
        .rowsGap(this.gridColumns >= 3 ? 14 : 18)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.bgColor)
    }
  }
}

@Component
export struct CameraGridCard {
  @Prop camera: CameraDevice = { id: '', name: '', rtspUrl: '', isRecording: false, isConnected: false };
  @Prop isSelected: boolean = false;
  @Prop isPlaying: boolean = false;
  @Prop accentColor: string = '#20B486';
  @Prop surfaceVariantColor: string = '#F0F1F5';
  @Prop onBackgroundColor: string = '#1B1B1D';
  @Prop onSurfaceVariantColor: string = '#6B6F76';
  @Prop secondaryContainerColor: string = '#D6F3E8';
  @Prop errorColor: string = '#E53935';
  @Prop surfaceColor: string = '#FFFFFF';
  @Prop outlineVariantColor: string = '#E0E2E8';
  onCardClick: () => void = () => {};
  onLongPress: () => void = () => {};

  build(): void {
    Column() {
      Stack() {
        if (this.camera.coverImagePath) {
          Image(`file://${this.camera.coverImagePath}`)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              direction: GradientDirection.Right,
              colors: [[this.surfaceVariantColor, 0.0], [this.isPlaying ? this.secondaryContainerColor : this.surfaceVariantColor, 1.0]]
            })
        }
      }
      .width('100%')
      .aspectRatio(1.55)
      .borderRadius(12)
      .clip(true)

      Row() {
        Text(this.camera.name || $r('app.string.unnamed'))
          .fontSize(16)
          .fontColor(this.onBackgroundColor)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Text(this.getStreamBadge())
          .fontSize(12)
          .fontColor(this.onSurfaceVariantColor)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor(this.surfaceVariantColor)
          .borderRadius(999)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
      .margin({ top: 10, bottom: 12 })
    }
    .width('100%')
    .onClick(() => this.onCardClick())
    .gesture(
      LongPressGesture()
        .onAction(() => this.onLongPress())
    )
  }

  private getStreamBadge(): string {
    const streamType = playbackStreamTypeFromUrl(this.camera.rtspUrl);
    if (streamType === PlaybackStreamType.RTSP) return 'RTSP';
    if (streamType === PlaybackStreamType.HTTP || streamType === PlaybackStreamType.HTTPS) return 'HTTP';
    if (streamType === PlaybackStreamType.RTMP) return 'RTMP';
    return getContext(this).resourceManager.getStringByNameSync('badge_cam');
  }

}

@Component
export struct PlaybackFullscreenScreen {
  @Prop camera: CameraDevice = { id: '', name: '', rtspUrl: '', isRecording: false, isConnected: false };
  @Prop badge: string = 'CAM';
  @Prop isPlaying: boolean = false;
  @Prop isMuted: boolean = false;
  @Prop isVideoReady: boolean = false;
  @Prop isRecording: boolean = false;
  @Prop accentColor: string = '#20B486';
  @Prop onPrimaryColor: string = '#FFFFFF';
  @Prop errorColor: string = '#E53935';
  @Prop surfaceVariantColor: string = '#F0F1F5';
  @Prop surfaceId: string = '';
  onBindSurface: (id: string) => void = () => {};
  onBack: () => void = () => {};
  onTogglePlayPause: () => void = () => {};
  onMute: () => void = () => {};
  onSnapshot: () => void = () => {};
  onToggleRecord: () => void = () => {};
  onMore: () => void = () => {};
  onSwipeLeft: () => void = () => {};
  onSwipeRight: () => void = () => {};
  @State controlsVisible: boolean = false;
  @State zoomScale: number = 1.0;
  @Prop videoWidth: number = 0;
  @Prop videoHeight: number = 0;
  @State containerWidth: number = 0;
  @State containerHeight: number = 0;
  private controlsTimerId: number = -1;
  private xComponentController: XComponentController = new XComponentController();

  aboutToDisappear(): void {
    if (this.controlsTimerId !== -1) {
      clearTimeout(this.controlsTimerId);
    }
  }

  private resetControlsTimer(): void {
    if (this.controlsTimerId !== -1) {
      clearTimeout(this.controlsTimerId);
    }
    if (this.controlsVisible && this.isPlaying) {
      this.controlsTimerId = setTimeout(() => {
        this.controlsVisible = false;
      }, 4000);
    }
  }

  private getContainWidth(): Length {
    if (this.videoWidth <= 0 || this.videoHeight <= 0) return '100%';
    if (this.containerWidth <= 0 || this.containerHeight <= 0) return '100%';
    const videoRatio = this.videoWidth / this.videoHeight;
    const containerRatio = this.containerWidth / this.containerHeight;
    return containerRatio > videoRatio ? this.containerHeight * videoRatio : this.containerWidth;
  }

  private getContainHeight(): Length {
    if (this.videoWidth <= 0 || this.videoHeight <= 0) return '100%';
    if (this.containerWidth <= 0 || this.containerHeight <= 0) return '100%';
    const videoRatio = this.videoWidth / this.videoHeight;
    const containerRatio = this.containerWidth / this.containerHeight;
    return containerRatio > videoRatio ? this.containerHeight : this.containerWidth / videoRatio;
  }

  build(): void {
    Stack() {
      Column() {
        XComponent({
          id: 'nvrVideoSurface',
          type: XCOMPONENT_TYPE_SURFACE,
          controller: this.xComponentController,
        })
          .onLoad(() => {
            const surfaceId = this.xComponentController.getXComponentSurfaceId();
            this.onBindSurface(surfaceId);
          })
          .width(this.getContainWidth())
          .height(this.getContainHeight())
          .scale({ x: this.zoomScale, y: this.zoomScale })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onAreaChange((_e: Area, area: Area) => {
        const w = Number(area.width);
        const h = Number(area.height);
        if (w > 0 && h > 0 && (w !== this.containerWidth || h !== this.containerHeight)) {
          this.containerWidth = w;
          this.containerHeight = h;
        }
      })
      .gesture(
        TapGesture({ count: 2 })
          .onAction(() => {
            if (this.zoomScale > 1.0) {
              this.zoomScale = 1.0;
            } else {
              this.zoomScale = 2.0;
            }
          })
      )
      .gesture(
        SwipeGesture({ speed: 100 })
          .onAction((event: GestureEvent) => {
            if (event.angle > -45 && event.angle < 45) {
              this.onSwipeLeft();
            } else if (event.angle > 135 || event.angle < -135) {
              this.onSwipeRight();
            }
          })
      )
      .gesture(
        PinchGesture({ fingers: 2 })
          .onActionEnd((event: GestureEvent) => {
            if (event.scale > 1.0) {
              this.zoomScale = Math.min(this.zoomScale * 1.3, 3.0);
            } else {
              this.zoomScale = Math.max(this.zoomScale / 1.3, 1.0);
            }
          })
      )

      if (!this.isVideoReady) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.accentColor)
          Text($r('app.string.loading_stream'))
            .fontSize(14)
            .fontColor('#FFFFFF')
            .margin({ top: 12 })
          Text($r('app.string.loading_buffer_hint'))
            .fontSize(11)
            .fontColor('#BEBEC2')
            .margin({ top: 4 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#CC000000')
      }

      if (this.controlsVisible) {
        Column() {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(28)
              .fontColor(['#FFFFFF'])
              .onClick(() => this.onBack())

            Text(this.camera.name || this.badge)
              .fontSize(20)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Bold)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .margin({ left: 16 })

            Text(this.badge)
              .fontSize(12)
              .fontColor('#BEBEC2')
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: [['#CC000000', 0.0], ['#00000000', 1.0]]
          })

          Blank()
            .width('100%')
            .layoutWeight(1)

          Row() {
            Row({ space: 16 }) {
              SymbolGlyph($r('sys.symbol.camera'))
                .fontSize(20)
                .fontColor(['#1B1B1D'])
                .width(36)
                .height(36)
                .onClick(() => this.onSnapshot())

              Stack() {
                SymbolGlyph(this.isRecording ? $r('sys.symbol.circle_fill') : $r('sys.symbol.record_circle'))
                  .fontSize(this.isRecording ? 18 : 20)
                  .fontColor([this.isRecording ? this.errorColor : '#6B6F76'])
              }
              .width(36)
              .height(36)
              .onClick(() => this.onToggleRecord())

              Stack() {
                Circle({ width: 44, height: 44 })
                  .fill('#1B1B1D')
                SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
                  .fontSize(22)
                  .fontColor(['#FFFFFF'])
              }
              .width(44)
              .height(44)
              .onClick(() => this.onTogglePlayPause())

              SymbolGlyph(this.isMuted ? $r('sys.symbol.speaker_slash') : $r('sys.symbol.speaker_wave_2'))
                .fontSize(20)
                .fontColor(['#1B1B1D'])
                .width(36)
                .height(36)
                .onClick(() => this.onMute())

              Stack() {
                Circle({ width: 22, height: 22 })
                  .fill(Color.Transparent)
                  .stroke('#1B1B1D')
                  .strokeWidth(1.5)
                Text('⋯')
                  .fontSize(11)
                  .fontColor('#1B1B1D')
              }
              .width(28)
              .height(28)
              .onClick(() => this.onMore())
            }
            .backgroundColor('#99FFFFFF')
            .borderRadius(99)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .padding({ top: 10, bottom: 18 })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .onClick(() => {
      this.controlsVisible = !this.controlsVisible;
      if (this.controlsVisible) {
        this.resetControlsTimer();
      }
    })
  }

  aboutToAppear(): void {
    this.resetControlsTimer();
  }
}

@Component
export struct NvrBottomBar {
  @Prop selectedTab: number = 0;
  @Prop accentColor: string = '#20B486';
  @Prop bgColor: string = '#F7F8FA';
  @Prop onSurfaceVariantColor: string = '#6B6F76';
  @Prop onPrimaryColor: string = '#FFFFFF';
  onTabSelected: (index: number) => void = () => {};

  build(): void {
    Row() {
      ForEach([
        { label: getContext(this).resourceManager.getStringByNameSync('tab_cameras'), icon: $r('sys.symbol.video_fill'), index: 0 },
        { label: getContext(this).resourceManager.getStringByNameSync('tab_browse'), icon: $r('sys.symbol.compass'), index: 1 },
        { label: getContext(this).resourceManager.getStringByNameSync('tab_activity'), icon: $r('sys.symbol.histogram'), index: 2 },
        { label: getContext(this).resourceManager.getStringByNameSync('tab_snapshots'), icon: $r('sys.symbol.camera_fill'), index: 3 },
        { label: getContext(this).resourceManager.getStringByNameSync('tab_settings'), icon: $r('sys.symbol.gearshape_fill'), index: 4 },
      ], (item: TabBarItem) => {
        Column() {
          SymbolGlyph(item.icon)
            .fontSize(22)
            .fontColor([this.selectedTab === item.index ? this.accentColor : this.onSurfaceVariantColor])
          Text(item.label)
            .fontSize(11)
            .fontColor(this.selectedTab === item.index ? this.accentColor : this.onSurfaceVariantColor)
            .fontWeight(this.selectedTab === item.index ? FontWeight.Bold : FontWeight.Medium)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 6, bottom: 6 })
        .borderRadius(18)
        .onClick(() => this.onTabSelected(item.index))
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.bgColor)
    .padding({ left: 6, right: 6, top: 8, bottom: 8 })
  }
}

@Component
export struct CameraActionOverlay {
  @Prop camera: CameraDevice = { id: '', name: '', rtspUrl: '', isRecording: false, isConnected: false };
  @Prop badge: string = 'CAM';
  @Prop accentColor: string = '#20B486';
  @Prop surfaceColor: string = '#FFFFFF';
  @Prop onSurfaceColor: string = '#1B1B1D';
  @Prop outlineVariantColor: string = '#E0E2E8';
  onDismiss: () => void = () => {};
  onEdit: () => void = () => {};
  onCopy: () => void = () => {};
  onDelete: () => void = () => {};

  build(): void {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#6B000000')
        .onClick(() => this.onDismiss())

      Column() {
        Text(this.camera.name || $r('app.string.unnamed'))
          .fontSize(18)
          .fontColor(this.onSurfaceColor)
          .fontWeight(FontWeight.Bold)
          .padding({ top: 16, bottom: 8 })

        Column() {
          Row() {
            Text($r('app.string.action_edit'))
              .fontSize(16)
              .fontColor(this.onSurfaceColor)
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.gearshape_fill'))
              .fontSize(20)
              .fontColor([this.onSurfaceColor])
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ left: 20, right: 20, top: 16, bottom: 16 })
          .onClick(() => this.onEdit())

          Divider().color(this.outlineVariantColor)

          Row() {
            Text($r('app.string.action_copy'))
              .fontSize(16)
              .fontColor(this.onSurfaceColor)
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.square_on_square_fill'))
              .fontSize(20)
              .fontColor([this.onSurfaceColor])
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ left: 20, right: 20, top: 16, bottom: 16 })
          .onClick(() => this.onCopy())

          Divider().color(this.outlineVariantColor)

          Row() {
            Text($r('app.string.action_delete'))
              .fontSize(16)
              .fontColor(this.onSurfaceColor)
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.trash_fill'))
              .fontSize(20)
              .fontColor([this.onSurfaceColor])
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ left: 20, right: 20, top: 16, bottom: 16 })
          .onClick(() => this.onDelete())
        }
        .width('72%')
        .borderRadius(18)
        .backgroundColor(this.surfaceColor)
        .margin({ top: 110 })
      }
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
  }
}
