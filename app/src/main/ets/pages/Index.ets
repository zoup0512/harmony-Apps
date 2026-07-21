import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

interface ModuleItem {
  name: string;
  title: string;
  desc: string;
  icon: string;
  color: string;
}

@Entry
@Component
struct Index {
  private modules: ModuleItem[] = [
    { name: 'cams', title: 'NVR 监控', desc: '网络摄像头监控', icon: '📷', color: '#2563EB' },
    { name: 'cameraviewer', title: 'IP Camera Viewer', desc: 'IP 摄像头查看器', icon: '🎥', color: '#0EA5E9' },
    { name: 'cammonitor', title: 'Cam Monitor', desc: 'IP 摄像头集中监控', icon: '🖥️', color: '#6366F1' },
    { name: 'streamshow', title: 'StreamShow', desc: '多通道视频墙(ONVIF)', icon: '🔲', color: '#14B8A6' },
    { name: 'ipwebcam', title: 'IP Webcam', desc: '手机变网络摄像头', icon: '📱', color: '#22C55E' },
    { name: 'infuse', title: 'Infuse Player', desc: '本地/网络视频播放', icon: '🎬', color: '#FF8C42' },
    { name: 'webvideocast', title: 'Web Video Cast', desc: '网页视频投屏', icon: '📺', color: '#EC4899' },
    { name: 'goweb', title: 'GoWeb', desc: '网页浏览器', icon: '🌐', color: '#10B981' },
    { name: 'guessnumber', title: '数字解密', desc: '1A2B 猜数字游戏', icon: '🔢', color: '#F59E0B' },
    { name: 'fastfurious', title: 'Fast & Furious', desc: '赛车游戏', icon: '🏎️', color: '#EF4444' },
    { name: 'grsaiagi', title: 'GRS AI', desc: 'AI 图像生成', icon: '🎨', color: '#8B5CF6' },
    { name: 'kart', title: 'Kart Racing', desc: '3D 卡丁车', icon: '🏁', color: '#F97316' },
    { name: 'memorygame', title: '记忆训练', desc: '大脑记忆训练游戏', icon: '🧠', color: '#06B6D4' }
  ];

  private launchModule(item: ModuleItem): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.startAbility({
      bundleName: 'com.razor.app',
      moduleName: item.name,
      abilityName: 'EntryAbility'
    }).then(() => {
      console.info(`Launched module: ${item.name}`);
    }).catch((err: Error) => {
      console.error(`Failed to launch module ${item.name}: ${err.message}`);
      promptAction.showToast({ message: `无法打开 ${item.title}: ${err.message}` });
    });
  }

  build() {
    Column() {
      Text('HarmonyApps')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1F2937')
        .margin({ top: 20, bottom: 4 })

      Text('应用合集')
        .fontSize(14)
        .fontColor('#6B7280')
        .margin({ bottom: 16 })

      List({ space: 12 }) {
        ForEach(this.modules, (item: ModuleItem) => {
          ListItem() {
            Row({ space: 14 }) {
              Column() {
                Text(item.icon)
                  .fontSize(28)
              }
              .width(56)
              .height(56)
              .backgroundColor(item.color)
              .borderRadius(16)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)

              Column({ space: 4 }) {
                Text(item.title)
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1F2937')
                Text(item.desc)
                  .fontSize(13)
                  .fontColor('#6B7280')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text('›')
                .fontSize(22)
                .fontColor('#9CA3AF')
            }
            .width('100%')
            .padding(14)
            .backgroundColor('#FFFFFF')
            .borderRadius(16)
            .shadow({ radius: 8, color: 'rgba(0,0,0,0.06)', offsetY: 2 })
            .onClick(() => {
              this.launchModule(item);
            })
          }
        }, (item: ModuleItem) => item.name)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F3F4F6')
  }
}
