import { router } from '@kit.ArkUI';
import common from '@ohos.app.ability.common';
import {
  MPTheme, MPDifficulty, getThemeById, getDifficulty,
  loadBest, saveBest, MPBest, calcStars, calcScore,
  MPSettings, MPMusic, colsTemplate, shuffleArr
} from '../common/MatchPairsCommon';

interface MPCard { id: number; imgIdx: number; matched: boolean; revealed: boolean; }

@Entry
@Component
struct MatchPairsGamePage {
  @State private themeId: number = 1;
  @State private level: number = 1;
  @State private theme: MPTheme = getThemeById(1);
  @State private diff: MPDifficulty = getDifficulty(1);

  @State private cards: MPCard[] = [];
  @State private flippedIds: number[] = [];
  @State private remainedToFlip: number = 0;

  // Timing
  @State private elapsedSec: number = 0;
  private startTs: number = 0;
  private pauseAccumMs: number = 0;
  private lastPauseTs: number = 0;
  private timerId: number = -1;

  // UI overlays
  @State private isPaused: boolean = false;
  @State private isWon: boolean = false;
  @State private isLost: boolean = false;
  @State private wonStars: number = 0;
  @State private wonScore: number = 0;
  @State private wonTime: number = 0;
  @State private isNewRecord: boolean = false;
  @State private showSettings: boolean = false;
  @State private musicOn: boolean = true;
  @State private sfxOn: boolean = true;

  private flowId: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    if (params) {
      if (params.themeId !== undefined) this.themeId = params.themeId as number;
      if (params.level !== undefined) this.level = params.level as number;
    }
    this.theme = getThemeById(this.themeId);
    this.diff = getDifficulty(this.level);

    const ctx = getContext(this) as common.UIAbilityContext;
    MPMusic.init(ctx);
    MPSettings.load(ctx).then(() => {
      this.musicOn = MPSettings.music();
      this.sfxOn = MPSettings.sfx();
      MPMusic.startBgm();
    });

    this.startGame();
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) clearInterval(this.timerId);
    this.flowId++;
    MPMusic.stopBgm();
  }

  // ── Game lifecycle ─────────────────────────────────────────────────────────
  private startGame(): void {
    this.flowId++;
    this.isPaused = false;
    this.isWon = false;
    this.isLost = false;
    this.flippedIds = [];

    // Build pairs: pick numPairs unique image indices, duplicate, shuffle
    const numPairs = this.diff.numTiles / 2;
    const pickIdx: number[] = [];
    const pool: number[] = [];
    for (let i = 0; i < this.theme.imageCount; i++) pool.push(i);
    const shuffledPool = shuffleArr(pool);
    for (let i = 0; i < numPairs; i++) pickIdx.push(shuffledPool[i]);

    const list: MPCard[] = [];
    for (let i = 0; i < numPairs; i++) {
      list.push({ id: i * 2,     imgIdx: pickIdx[i], matched: false, revealed: false });
      list.push({ id: i * 2 + 1, imgIdx: pickIdx[i], matched: false, revealed: false });
    }
    this.cards = shuffleArr(list);
    this.remainedToFlip = this.diff.numTiles;

    // Reset clock
    this.elapsedSec = 0;
    this.pauseAccumMs = 0;
    this.startTs = Date.now();
    this.startTimer();
  }

  private startTimer(): void {
    if (this.timerId !== -1) clearInterval(this.timerId);
    this.timerId = setInterval(() => {
      const elapsedMs = Date.now() - this.startTs - this.pauseAccumMs;
      const sec = Math.floor(elapsedMs / 1000);
      this.elapsedSec = sec;
      if (sec >= this.diff.timeSec && !this.isWon && !this.isLost) {
        this.handleTimeout();
      }
    }, 200);
  }

  private stopTimer(): void {
    if (this.timerId !== -1) { clearInterval(this.timerId); this.timerId = -1; }
  }

  // ── Card tapping ───────────────────────────────────────────────────────────
  private onCardTap(idx: number): void {
    if (this.isPaused || this.isWon || this.isLost) return;
    const card = this.cards[idx];
    if (card.matched || card.revealed) return;
    if (this.flippedIds.length >= 2) return;

    // Reveal this card
    const newCards = this.cards.map((c: MPCard, i: number) =>
      i === idx ? ({ id: c.id, imgIdx: c.imgIdx, matched: c.matched, revealed: true } as MPCard) : c);
    this.cards = newCards;
    const newFlipped = [...this.flippedIds, idx];
    this.flippedIds = newFlipped;

    if (newFlipped.length === 2) {
      const a = newCards[newFlipped[0]];
      const b = newCards[newFlipped[1]];
      if (a.imgIdx === b.imgIdx) {
        // Match
        const fid = ++this.flowId;
        setTimeout(() => {
          if (fid !== this.flowId) return;
          MPMusic.playCorrect();
          const matched = this.cards.map((c: MPCard, i: number) =>
            (i === newFlipped[0] || i === newFlipped[1])
              ? ({ id: c.id, imgIdx: c.imgIdx, matched: true, revealed: true } as MPCard) : c);
          this.cards = matched;
          this.flippedIds = [];
          this.remainedToFlip = this.remainedToFlip - 2;
          if (this.remainedToFlip === 0) this.handleWin();
        }, 700);
      } else {
        // Mismatch — flip back
        const fid = ++this.flowId;
        setTimeout(() => {
          if (fid !== this.flowId) return;
          MPMusic.playWrong();
          const flipBack = this.cards.map((c: MPCard, i: number) =>
            (i === newFlipped[0] || i === newFlipped[1])
              ? ({ id: c.id, imgIdx: c.imgIdx, matched: c.matched, revealed: false } as MPCard) : c);
          this.cards = flipBack;
          this.flippedIds = [];
        }, 1000);
      }
    }
  }

  private handleWin(): void {
    this.stopTimer();
    const passed = this.elapsedSec;
    const total = this.diff.timeSec;
    const stars = calcStars(passed, total);
    const score = calcScore(this.level, total - passed, this.themeId);
    this.wonStars = stars;
    this.wonScore = score;
    this.wonTime = passed;
    if (stars === 3) MPMusic.playStar();

    // Persist best
    const ctx = getContext(this) as common.UIAbilityContext;
    loadBest(ctx, this.themeId, this.level).then((old: MPBest) => {
      const isBetter = stars > old.stars || old.timeSec === 0 || (passed > 0 && passed < old.timeSec);
      this.isNewRecord = isBetter;
      saveBest(ctx, this.themeId, this.level, stars, passed);
    });

    this.isWon = true;
  }

  private handleTimeout(): void {
    this.stopTimer();
    this.isLost = true;
  }

  // ── Pause handling ─────────────────────────────────────────────────────────
  private doPause(): void {
    if (this.isWon || this.isLost) return;
    this.isPaused = true;
    this.lastPauseTs = Date.now();
    this.stopTimer();
  }

  private doResume(): void {
    if (this.lastPauseTs > 0) {
      this.pauseAccumMs += Date.now() - this.lastPauseTs;
      this.lastPauseTs = 0;
    }
    this.isPaused = false;
    this.startTimer();
  }

  // ── Settings ───────────────────────────────────────────────────────────────
  private async toggleMusic(): Promise<void> {
    const next = !this.musicOn;
    const ctx = getContext(this) as common.UIAbilityContext;
    await MPSettings.setMusic(ctx, next);
    this.musicOn = next;
    if (next) MPMusic.startBgm(); else MPMusic.stopBgm();
  }

  private async toggleSfx(): Promise<void> {
    const next = !this.sfxOn;
    const ctx = getContext(this) as common.UIAbilityContext;
    await MPSettings.setSfx(ctx, next);
    this.sfxOn = next;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  private fmtTime(sec: number): string {
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  }

  private timerColor(): string {
    const ratio = this.elapsedSec / this.diff.timeSec;
    if (ratio < 0.5) return '#4CAF50';
    if (ratio < 0.8) return '#FF9800';
    return '#F44336';
  }

  private nextLevelOrNull(): number {
    if (this.wonStars === 3 && this.level < 6) return this.level + 1;
    return -1;
  }

  // ── Card builder (3D Y-axis flip) ─────────────────────────────────────────
  @Builder
  private CardView(card: MPCard, idx: number) {
    Stack() {
      // Card chrome
      Column().width('100%').height('100%').borderRadius(6)
        .backgroundColor(card.matched ? '#E8F5E9' : '#FFFFFF')
        .border({ width: 1, color: card.matched ? '#4CAF50' : '#BDBDBD' })

      // BACK face: visible when not revealed; rotates to 90° (edge-on) when flipping
      Image(this.theme.cardBack)
        .width('92%').height('92%').objectFit(ImageFit.Contain)
        .rotate({ x: 0, y: 1, z: 0, angle: card.revealed ? 90 : 0, centerX: '50%', centerY: '50%' })
        .opacity(card.revealed ? 0 : 1)
        .animation({ duration: 200, curve: Curve.EaseIn })

      // FRONT face: comes in after back disappears
      Image(this.theme.images[card.imgIdx])
        .width('92%').height('92%').objectFit(ImageFit.Contain)
        .rotate({ x: 0, y: 1, z: 0, angle: card.revealed ? 0 : -90, centerX: '50%', centerY: '50%' })
        .opacity(card.revealed ? (card.matched ? 0.55 : 1.0) : 0)
        .animation({ duration: 200, curve: Curve.EaseOut, delay: 200 })
    }.width('100%').height('100%').onClick(() => this.onCardTap(idx))
  }

  build() {
    Stack() {
      // Background image
      Image(this.theme.bgImage).width('100%').height('100%').objectFit(ImageFit.Cover)
      Column().width('100%').height('100%').backgroundColor('#66FFFFFF')

      // ── Main Column ────────────────────────────────────────────────────
      Column() {
        // Top bar
        Row() {
          Button({ type: ButtonType.Circle }) {
            Text('‹').fontSize(24).fontColor('#FFF').fontWeight(FontWeight.Bold)
          }.width(36).height(36).backgroundColor('#9E9E9E').onClick(() => router.back())

          Column() {
            Text(`${this.theme.name} · 第 ${this.level} 关`).fontSize(15).fontColor('#212121').fontWeight(FontWeight.Bold)
            Text(`${this.diff.cols}×${this.diff.rows} · ${this.diff.numTiles} 张牌`).fontSize(11).fontColor('#424242')
          }.alignItems(HorizontalAlign.Start).margin({ left: 12 }).layoutWeight(1)

          // Timer ring
          Stack() {
            Progress({ value: this.elapsedSec, total: this.diff.timeSec, type: ProgressType.Ring })
              .width(56).height(56).color(this.timerColor()).style({ strokeWidth: 6 })
            Text(this.fmtTime(Math.max(0, this.diff.timeSec - this.elapsedSec)))
              .fontSize(12).fontColor('#212121').fontWeight(FontWeight.Bold)
          }

          Button({ type: ButtonType.Circle }) {
            Text('⚙').fontSize(20).fontColor('#FFF')
          }.width(36).height(36).backgroundColor('#673AB7').margin({ left: 8 })
          .onClick(() => { this.doPause(); this.showSettings = true; })

          Button({ type: ButtonType.Circle }) {
            Text('‖').fontSize(18).fontColor('#FFF').fontWeight(FontWeight.Bold)
          }.width(36).height(36).backgroundColor('#FF9800').margin({ left: 6 })
          .onClick(() => this.doPause())
        }.width('100%').padding({ left: 12, right: 12, top: 12, bottom: 12 })
        .backgroundColor('#CCFFFFFF')

        // Board
        Column() {
          Grid() {
            ForEach(this.cards, (card: MPCard, idx: number) => {
              GridItem() {
                this.CardView(card, idx)
              }.aspectRatio(1)
            }, (card: MPCard, idx: number) => `mpc_${this.level}_${idx}_${card.id}`)
          }
          .columnsTemplate(colsTemplate(this.diff.cols))
          .rowsGap(this.diff.cols >= 8 ? 3 : 6)
          .columnsGap(this.diff.cols >= 8 ? 3 : 6)
          .width('100%')
        }.width('96%').layoutWeight(1).justifyContent(FlexAlign.Center).padding({ top: 8, bottom: 8 })
      }.width('100%').height('100%')

      // ── Pause overlay ───────────────────────────────────────────────────
      if (this.isPaused && !this.showSettings && !this.isWon && !this.isLost) {
        Stack() {
          Column().width('100%').height('100%').backgroundColor('#88000000')
          Column({ space: 16 }) {
            Text('已暂停').fontSize(28).fontWeight(FontWeight.Bold).fontColor('#212121')
            Button('继续', { type: ButtonType.Capsule })
              .width(180).height(44).backgroundColor('#4CAF50').fontColor('#FFF')
              .onClick(() => this.doResume())
            Button('重新开始', { type: ButtonType.Capsule })
              .width(180).height(44).backgroundColor('#1976D2').fontColor('#FFF')
              .onClick(() => this.startGame())
            Button('返回', { type: ButtonType.Capsule })
              .width(180).height(44).backgroundColor('#9E9E9E').fontColor('#FFF')
              .onClick(() => router.back())
          }.padding(28).backgroundColor('#FFF').borderRadius(20)
        }.width('100%').height('100%')
      }

      // ── Settings popup ──────────────────────────────────────────────────
      if (this.showSettings) {
        Stack() {
          Column().width('100%').height('100%').backgroundColor('#88000000')
          Column({ space: 18 }) {
            Text('设置').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#212121')
            Row() {
              Text('🎵  背景音乐').fontSize(16).fontColor('#212121').layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.musicOn }).onChange(() => this.toggleMusic())
            }.width('100%')
            Row() {
              Text('🔔  音效').fontSize(16).fontColor('#212121').layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.sfxOn }).onChange(() => this.toggleSfx())
            }.width('100%')
            Button('关闭', { type: ButtonType.Capsule })
              .width(160).height(40).backgroundColor('#1976D2').fontColor('#FFF')
              .onClick(() => { this.showSettings = false; if (!this.isWon && !this.isLost) this.doResume(); })
          }.padding(24).width(280).backgroundColor('#FFF').borderRadius(20)
        }.width('100%').height('100%')
      }

      // ── Win popup ───────────────────────────────────────────────────────
      if (this.isWon) {
        Stack() {
          Column().width('100%').height('100%').backgroundColor('#88000000')
          Column({ space: 14 }) {
            Text('🎉 通关！').fontSize(28).fontWeight(FontWeight.Bold).fontColor('#4CAF50')
            Row({ space: 8 }) {
              ForEach([1, 2, 3] as number[], (i: number) => {
                Text(i <= this.wonStars ? '★' : '☆').fontSize(40)
                  .fontColor(i <= this.wonStars ? '#FFB300' : '#BDBDBD')
              }, (i: number) => `won_star_${i}`)
            }
            if (this.isNewRecord) {
              Text('🏆 新纪录！').fontSize(14).fontColor('#FF5722').fontWeight(FontWeight.Bold)
            }
            Text(`用时 ${this.fmtTime(this.wonTime)}`).fontSize(15).fontColor('#424242')
            Text(`得分 ${this.wonScore}`).fontSize(15).fontColor('#424242')

            if (this.nextLevelOrNull() !== -1) {
              Button(`下一关 ▶`, { type: ButtonType.Capsule })
                .width(180).height(44).backgroundColor('#4CAF50').fontColor('#FFF')
                .onClick(() => {
                  this.level = this.nextLevelOrNull();
                  this.diff = getDifficulty(this.level);
                  this.startGame();
                })
            }
            Button('再来一局', { type: ButtonType.Capsule })
              .width(180).height(44).backgroundColor('#1976D2').fontColor('#FFF')
              .onClick(() => this.startGame())
            Button('返回难度', { type: ButtonType.Capsule })
              .width(180).height(44).backgroundColor('#9E9E9E').fontColor('#FFF')
              .onClick(() => router.back())
          }.padding(24).backgroundColor('#FFF').borderRadius(20)
        }.width('100%').height('100%')
      }

      // ── Lose (timeout) popup ────────────────────────────────────────────
      if (this.isLost) {
        Stack() {
          Column().width('100%').height('100%').backgroundColor('#88000000')
          Column({ space: 14 }) {
            Text('⏰ 时间到').fontSize(26).fontWeight(FontWeight.Bold).fontColor('#F44336')
            Text('再接再厉！').fontSize(15).fontColor('#616161')
            Button('再来一局', { type: ButtonType.Capsule })
              .width(180).height(44).backgroundColor('#1976D2').fontColor('#FFF')
              .onClick(() => this.startGame())
            Button('返回难度', { type: ButtonType.Capsule })
              .width(180).height(44).backgroundColor('#9E9E9E').fontColor('#FFF')
              .onClick(() => router.back())
          }.padding(24).backgroundColor('#FFF').borderRadius(20)
        }.width('100%').height('100%')
      }
    }.width('100%').height('100%')
  }
}
