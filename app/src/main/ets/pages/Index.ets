import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

interface ModuleItem {
  name: string;
  title: string;
  desc: string;
  icon: string;
  color: string;
}

interface ModuleGroup {
  title: string;
  icon: string;
  items: ModuleItem[];
}

@Entry
@Component
struct Index {
  private groups: ModuleGroup[] = [
    {
      title: '视频监控',
      icon: '📹',
      items: [
        { name: 'cams', title: 'NVR 监控', desc: '网络摄像头监控', icon: '📷', color: '#2563EB' },
        { name: 'cameraviewer', title: 'IP Camera Viewer', desc: 'IP 摄像头查看器', icon: '🎥', color: '#0EA5E9' },
        { name: 'cammonitor', title: 'Cam Monitor', desc: 'IP 摄像头集中监控', icon: '🖥️', color: '#6366F1' },
        { name: 'streamshow', title: 'StreamShow', desc: '多通道视频墙(ONVIF)', icon: '🔲', color: '#14B8A6' },
        { name: 'ipwebcam', title: 'IP Webcam', desc: '手机变网络摄像头', icon: '📱', color: '#22C55E' }
      ]
    },
    {
      title: '影音播放',
      icon: '🎬',
      items: [
        { name: 'infuse', title: 'Infuse Player', desc: '本地/网络视频播放', icon: '🎬', color: '#FF8C42' },
        { name: 'webvideocast', title: 'Web Video Cast', desc: '网页视频投屏', icon: '📺', color: '#EC4899' }
      ]
    },
    {
      title: '游戏娱乐',
      icon: '�',
      items: [
        { name: 'guessnumber', title: '数字解密', desc: '1A2B 猜数字游戏', icon: '🔢', color: '#F59E0B' },
        { name: 'fastfurious', title: 'Fast & Furious', desc: '赛车游戏', icon: '🏎️', color: '#EF4444' },
        { name: 'kart', title: 'Kart Racing', desc: '3D 卡丁车', icon: '�', color: '#F97316' },
        { name: 'memorygame', title: '记忆训练', desc: '大脑记忆训练游戏', icon: '🧠', color: '#06B6D4' }
      ]
    },
    {
      title: '工具应用',
      icon: '🛠️',
      items: [
        { name: 'goweb', title: 'GoWeb', desc: '网页浏览器', icon: '�', color: '#10B981' },
        { name: 'grsaiagi', title: 'GRS AI', desc: 'AI 图像生成', icon: '🎨', color: '#8B5CF6' }
      ]
    }
  ];

  private launchModule(item: ModuleItem): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.startAbilityForResult({
      bundleName: 'com.razor.app',
      moduleName: item.name,
      abilityName: 'EntryAbility'
    }).then((result) => {
      console.info(`Launched module: ${item.name}`);
      console.info(`Module ${item.name} finished, resultCode: ${result?.resultCode}`);
    }).catch((err: Error) => {
      console.error(`Failed to launch module ${item.name}: ${err.message}`);
      promptAction.showToast({ message: `无法打开 ${item.title}: ${err.message}` });
    });
  }

  @Builder
  moduleItemBuilder(item: ModuleItem) {
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

      Scroll() {
        Column() {
          ForEach(this.groups, (group: ModuleGroup, groupIndex: number) => {
            Row({ space: 8 }) {
              Text(group.icon)
                .fontSize(20)
              Text(group.title)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor('#374151')
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({
              top: groupIndex === 0 ? 0 : 20,
              bottom: 10,
              left: 4
            })

            ForEach(group.items, (item: ModuleItem) => {
              this.moduleItemBuilder(item)
            }, (item: ModuleItem) => item.name)
          }, (group: ModuleGroup) => group.title)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 20 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F3F4F6')
  }
}
