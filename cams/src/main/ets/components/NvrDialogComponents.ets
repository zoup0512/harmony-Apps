import { RecordingFile } from '../model/RecordingFile';
import { fileIo } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';

function safeShowToast(message: string): void {
  try {
    promptAction.openToast({ message });
  } catch (e) {
    console.error(`showToast failed: ${(e as Error).message}`);
  }
}

@Component
export struct RecordingPreviewDialog {
  dialogFile: RecordingFile = {
    id: '', fileName: '', filePath: '', fileSize: 0,
    startTime: null, endTime: null, cameraId: '', cameraName: ''
  };
  accentColor: string = '#20B486';
  onDismiss: () => void = () => {};

  build(): void {
    Column() {
      Text(this.dialogFile.fileName)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1B1B1D')
        .padding({ top: 24, left: 24, right: 24 })

      Text(this.dialogFile.filePath)
        .fontSize(14)
        .fontColor('#6B6F76')
        .padding({ left: 24, right: 24, top: 8 })

      if (this.isImageFile()) {
        Image(this.dialogFile.filePath)
          .width('85%')
          .height(260)
          .objectFit(ImageFit.Contain)
          .margin({ top: 16 })
      }

      Text($r('app.string.dialog_close'))
        .fontSize(16)
        .fontColor(this.accentColor)
        .fontWeight(FontWeight.Medium)
        .padding({ top: 24, bottom: 24, left: 24, right: 24 })
        .onClick(() => this.onDismiss())
    }
    .width('85%')
    .borderRadius(20)
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Center)
  }

  private isImageFile(): boolean {
    const ext = this.dialogFile.filePath.split('.').pop()?.toLowerCase() ?? '';
    return ['png', 'jpg', 'jpeg', 'webp'].includes(ext);
  }
}

@Component
export struct DeleteSnapshotConfirmDialog {
  fileName: string = '';
  accentColor: string = '#20B486';
  errorColor: string = '#E53935';
  onDismiss: () => void = () => {};
  onConfirmDelete: () => void = () => {};

  build(): void {
    Column() {
      Text($r('app.string.dialog_delete_snapshot_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1B1B1D')
        .padding({ top: 24, left: 24, right: 24 })

      Text(this.fileName)
        .fontSize(14)
        .fontColor('#6B6F76')
        .padding({ left: 24, right: 24, top: 8 })

      Row() {
        Text($r('app.string.dialog_cancel'))
          .fontSize(16)
          .fontColor('#6B6F76')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 16, bottom: 16 })
          .onClick(() => this.onDismiss())

        Text($r('app.string.dialog_delete'))
          .fontSize(16)
          .fontColor(this.errorColor)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 16, bottom: 16 })
          .onClick(() => this.onConfirmDelete())
      }
      .width('100%')
      .margin({ top: 24 })
    }
    .width('80%')
    .borderRadius(20)
    .backgroundColor('#FFFFFF')
  }
}

@Component
export struct ConfirmActionDialog {
  title: string = '';
  message: string = '';
  confirmLabel: string = '';
  cancelLabel: string = '';
  accentColor: string = '#20B486';
  errorColor: string = '#E53935';
  onDismiss: () => void = () => {};
  onConfirmAction: () => void = () => {};

  build(): void {
    Column() {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1B1B1D')
        .padding({ top: 24, left: 24, right: 24 })

      Text(this.message)
        .fontSize(14)
        .fontColor('#6B6F76')
        .padding({ left: 24, right: 24, top: 8 })

      Row() {
        Text(this.cancelLabel)
          .fontSize(16)
          .fontColor('#6B6F76')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 16, bottom: 16 })
          .onClick(() => this.onDismiss())

        Text(this.confirmLabel)
          .fontSize(16)
          .fontColor(this.errorColor)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 16, bottom: 16 })
          .onClick(() => this.onConfirmAction())
      }
      .width('100%')
      .margin({ top: 24 })
    }
    .width('80%')
    .borderRadius(20)
    .backgroundColor('#FFFFFF')
  }
}

@Component
export struct FeedbackDialog {
  accentColor: string = '#20B486';
  onLater: () => void = () => {};
  onRate: () => void = () => {};

  build(): void {
    Column() {
      Text($r('app.string.dialog_feedback_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1B1B1D')
        .width('100%')
        .padding({ top: 24, left: 24, right: 24 })

      Text($r('app.string.dialog_feedback_message'))
        .fontSize(14)
        .fontColor('#6B6F76')
        .width('100%')
        .padding({ left: 24, right: 24, top: 12 })

      Divider()
        .color('#E5E5E5')
        .margin({ top: 20 })

      Row() {
        Text($r('app.string.dialog_feedback_later'))
          .fontSize(16)
          .fontColor('#6B6F76')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 16, bottom: 16 })
          .onClick(() => this.onLater())

        Divider()
          .vertical(true)
          .color('#E5E5E5')
          .height(48)

        Text($r('app.string.dialog_feedback_rate'))
          .fontSize(16)
          .fontColor(this.accentColor)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 16, bottom: 16 })
          .onClick(() => this.onRate())
      }
      .width('100%')
    }
    .width('80%')
    .borderRadius(20)
    .backgroundColor('#FFFFFF')
  }
}

@Component
export struct SetPinDialog {
  accentColor: string = '#20B486';
  errorColor: string = '#E53935';
  onDismiss: () => void = () => {};
  onConfirm: (pin: string) => void = () => {};
  @State pin: string = '';
  @State confirmPin: string = '';

  private validateAndSubmit(): void {
    if (!/^\d{4}$/.test(this.pin)) {
      safeShowToast(getContext(this).resourceManager.getStringByNameSync('toast_pin_invalid_length'));
      return;
    }
    if (this.pin !== this.confirmPin) {
      safeShowToast(getContext(this).resourceManager.getStringByNameSync('toast_pin_mismatch'));
      return;
    }
    this.onConfirm(this.pin);
  }

  build(): void {
    Column() {
      Text($r('app.string.dialog_set_pin_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1B1B1D')
        .padding({ top: 24, left: 24, right: 24 })

      TextInput({ text: this.pin, placeholder: $r('app.string.dialog_set_pin_hint') })
        .fontSize(18)
        .type(InputType.Number)
        .maxLength(4)
        .backgroundColor('#F0F1F5')
        .borderRadius(12)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .margin({ left: 24, right: 24, top: 16 })
        .onChange((v: string) => { this.pin = v; })

      TextInput({ text: this.confirmPin, placeholder: $r('app.string.dialog_confirm_pin_hint') })
        .fontSize(18)
        .type(InputType.Number)
        .maxLength(4)
        .backgroundColor('#F0F1F5')
        .borderRadius(12)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .margin({ left: 24, right: 24, top: 12 })
        .onChange((v: string) => { this.confirmPin = v; })

      Row() {
        Text($r('app.string.dialog_cancel'))
          .fontSize(16)
          .fontColor('#6B6F76')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 16, bottom: 16 })
          .onClick(() => this.onDismiss())

        Text($r('app.string.dialog_confirm'))
          .fontSize(16)
          .fontColor(this.accentColor)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 16, bottom: 16 })
          .onClick(() => this.validateAndSubmit())
      }
      .width('100%')
      .margin({ top: 20 })
    }
    .width('80%')
    .borderRadius(20)
    .backgroundColor('#FFFFFF')
    .padding({ bottom: 8 })
  }
}
