import { router } from '@kit.ArkUI';
import { GamePauseDialog, GameOverOverlay, GameTopBar, stars3, fmtTime, randInt, shuffled } from '../common/GameCommon';

// "唯一的" — tap the unique element (game id=24)
const SHAPES: string[] = ['●', '■', '▲', '★'];
const COLORS: string[] = ['#F44336', '#2196F3', '#4CAF50', '#FFC107', '#9C27B0', '#FF9800'];
const GAME_TIME_MS = 60000;

interface OElem { shape: number; color: number; isWin: boolean; }

@Entry
@Component
struct OneAndOnlyPage {
  @State private level: number = 1;
  @State private score: number = 0;
  @State private timeMs: number = GAME_TIME_MS;
  @State private elems: OElem[] = [];
  @State private gridCols: number = 3;
  @State private failedIdx: number = -1;
  @State private isPaused: boolean = false;
  @State private isGameOver: boolean = false;
  private timerId: number = -1;
  private startTs: number = 0;
  private flowId: number = 0;

  aboutToAppear(): void { this.startGame(); }
  aboutToDisappear(): void { if (this.timerId !== -1) clearInterval(this.timerId); this.flowId++; }

  private startGame(): void {
    this.flowId++;
    this.level = 1; this.score = 0; this.timeMs = GAME_TIME_MS;
    this.isPaused = false; this.isGameOver = false; this.failedIdx = -1;
    this.startTimer();
    this.newLevel();
  }

  private startTimer(): void {
    if (this.timerId !== -1) clearInterval(this.timerId);
    this.startTs = Date.now();
    const initial = this.timeMs;
    this.timerId = setInterval(() => {
      const rem = initial - (Date.now() - this.startTs);
      if (rem <= 0) { this.timeMs = 0; this.endGame(); }
      else this.timeMs = rem;
    }, 100);
  }

  private newLevel(): void {
    const level = Math.min(this.level, 30);
    const numGroups = level <= 2 ? 1 : level <= 5 ? 2 : level <= 10 ? 3 : 4;
    const totalCount = level + 1;
    const colorsCount = level <= 3 ? 2 : 3;

    // Build groups: groups[0] = 1 (unique), groups[1..numGroups] = 2 each, distribute remainder
    const groups: number[] = [];
    groups.push(1);
    for (let i = 0; i < numGroups; i++) groups.push(2);
    let remaining = totalCount - numGroups * 2 - 1;
    while (remaining > 0) {
      const r = randInt(1, numGroups);
      groups[r] = groups[r] + 1;
      remaining--;
    }

    const palette = shuffled([0, 1, 2, 3, 4, 5]).slice(0, colorsCount);
    const repElems: OElem[] = [];
    for (let i = 0; i < groups.length; i++) {
      repElems.push({ color: palette[i % palette.length], shape: randInt(0, SHAPES.length - 1), isWin: false });
    }
    repElems[0].isWin = true;

    const result: OElem[] = [];
    for (let i = 0; i < groups.length; i++) {
      for (let k = 0; k < groups[i]; k++) result.push(repElems[i]);
    }
    this.elems = shuffled(result);
    this.gridCols = totalCount <= 4 ? 2 : totalCount <= 9 ? 3 : totalCount <= 16 ? 4 : 5;
    this.failedIdx = -1;
  }

  private tap(idx: number): void {
    if (this.isPaused || this.isGameOver) return;
    const e = this.elems[idx];
    if (e.isWin) {
      this.score = this.score + 8 + this.level * 2;
      this.level = this.level + 1;
      this.newLevel();
    } else {
      this.failedIdx = idx;
      const fid = ++this.flowId;
      setTimeout(() => { if (fid === this.flowId) this.failedIdx = -1; }, 300);
    }
  }

  private endGame(): void { if (this.timerId !== -1) clearInterval(this.timerId); this.timerId = -1; this.isGameOver = true; }

  build() {
    Stack() {
      Column() {
        GameTopBar({ title: '唯一的', scoreText: `分: ${this.score}`,
          onPause: () => { if (!this.isGameOver) { if (this.timerId !== -1) clearInterval(this.timerId); this.timerId = -1; this.isPaused = true; } }
        })
        Row() {
          Text(`关卡 ${this.level}`).fontSize(14).fontColor('#616161')
          Blank()
          Text(`⏱ ${fmtTime(this.timeMs)}`).fontSize(14).fontColor(this.timeMs <= 10000 ? '#F44336' : '#424242')
        }.width('100%').padding({ left: 16, right: 16, bottom: 8 })

        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height(4).backgroundColor('#E0E0E0').borderRadius(2)
          Row().width(`${(this.timeMs / GAME_TIME_MS * 100).toFixed(1)}%`).height(4)
            .backgroundColor(this.timeMs > 20000 ? '#4CAF50' : this.timeMs > 10000 ? '#FF9800' : '#F44336').borderRadius(2)
        }.width('90%').margin({ bottom: 12 })

        Text('找出独一无二的那一个').fontSize(15).fontColor('#616161').margin({ bottom: 12 })

        Column() {
          Grid() {
            ForEach(this.elems, (e: OElem, idx: number) => {
              GridItem() {
                Stack() {
                  Column().width('100%').height('100%')
                    .backgroundColor(this.failedIdx === idx ? '#FFCDD2' : '#FFFFFF').borderRadius(12)
                    .border({ width: 2, color: this.failedIdx === idx ? '#F44336' : '#E0E0E0' })
                    .animation({ duration: 150, curve: Curve.EaseOut })
                  Text(SHAPES[e.shape]).fontSize(44).fontColor(COLORS[e.color])
                }.width('100%').height('100%').onClick(() => this.tap(idx))
              }.aspectRatio(1)
            }, (e: OElem, idx: number) => `oao_${idx}_${this.level}`)
          }
          .columnsTemplate(this.gridCols === 2 ? '1fr 1fr' : this.gridCols === 3 ? '1fr 1fr 1fr' : this.gridCols === 4 ? '1fr 1fr 1fr 1fr' : '1fr 1fr 1fr 1fr 1fr')
          .columnsGap(8).rowsGap(8)
          .width('100%')
        }.width('92%').layoutWeight(1)

        Text(' ').height(16)
      }.width('100%').height('100%').backgroundColor('#F5F5F5')

      GamePauseDialog({ visible: this.isPaused, gameName: '唯一的',
        onResume: () => { this.isPaused = false; this.startTimer(); },
        onRestart: () => { this.isPaused = false; this.startGame(); },
        onExit: () => router.back()
      })
      GameOverOverlay({ visible: this.isGameOver, score: this.score, level: this.level,
        stars: stars3(this.level, 30, 20, 10),
        onPlayAgain: () => this.startGame(), onExit: () => router.back()
      })
    }.width('100%').height('100%')
  }
}
