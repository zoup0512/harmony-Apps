import { router } from '@kit.ArkUI';

// ─── Data types ────────────────────────────────────────────────────────────────

interface GameEntry {
  id: number;
  name: string;
  description: string;
  category: string;
}

interface CategoryEntry {
  id: string;
  name: string;
  color: string;
  icon: string;
}

// ─── Game categories ───────────────────────────────────────────────────────────

const CAT_ALL = 'ALL';
const CAT_MEMORY = 'MEMORY';
const CAT_ATTENTION = 'ATTENTION';
const CAT_SPEED = 'SPEED';
const CAT_PROBLEM = 'PROBLEM_SOLVING';
const CAT_FLEXIBILITY = 'FLEXIBILITY';
const CAT_IMAGINATION = 'IMAGINATION';

const CATEGORIES: CategoryEntry[] = [
  { id: CAT_ALL,        name: '全部',   color: '#757575', icon: '◈' },
  { id: CAT_MEMORY,     name: '记忆',   color: '#03A9F4', icon: '◉' },
  { id: CAT_ATTENTION,  name: '注意力', color: '#009688', icon: '◎' },
  { id: CAT_SPEED,      name: '速度',   color: '#F44336', icon: '◆' },
  { id: CAT_PROBLEM,    name: '问题解决', color: '#673AB7', icon: '◧' },
  { id: CAT_FLEXIBILITY,name: '灵活性', color: '#FFC107', icon: '⇄' },
  { id: CAT_IMAGINATION,name: '想象力', color: '#00BCD4', icon: '◈' },
];

function categoryColor(cat: string): string {
  switch (cat) {
    case CAT_MEMORY:      return '#03A9F4';
    case CAT_ATTENTION:   return '#009688';
    case CAT_SPEED:       return '#F44336';
    case CAT_PROBLEM:     return '#673AB7';
    case CAT_FLEXIBILITY: return '#FFC107';
    case CAT_IMAGINATION: return '#00BCD4';
    default:              return '#757575';
  }
}

function categoryIcon(cat: string): string {
  switch (cat) {
    case CAT_MEMORY:      return '🧠';
    case CAT_ATTENTION:   return '👁';
    case CAT_SPEED:       return '⚡';
    case CAT_PROBLEM:     return '🧩';
    case CAT_FLEXIBILITY: return '↔';
    case CAT_IMAGINATION: return '💡';
    default:              return '◈';
  }
}

function gamePageUrl(id: number): string {
  switch (id) {
    case 1:  return 'pages/MemoryGridPage';
    case 2:  return 'pages/HexagonsPage';
    case 3:  return 'pages/WhosNewPage';
    case 4:  return 'pages/RotatingGridPage';
    case 5:  return 'pages/FollowThePathPage';
    case 6:  return 'pages/ImageVortexPage';
    case 7:  return 'pages/CatchThemPage';
    case 8:  return 'pages/FindThePicturePage';
    case 11: return 'pages/MoreLessPage';
    case 12: return 'pages/AllTheSamePage';
    case 13: return 'pages/SortTheDigitsPage';
    case 14: return 'pages/PaperPlanesPage';
    case 15: return 'pages/LikePreviousPage';
    case 16: return 'pages/Game248Page';
    case 17: return 'pages/PyramidsPage';
    case 18: return 'pages/FindAllPage';
    case 19: return 'pages/CountEmAllPage';
    case 20: return 'pages/SymmetryPage';
    case 21: return 'pages/LaserPage';
    case 22: return 'pages/SchultzTablesPage';
    case 24: return 'pages/OneAndOnlyPage';
    case 25: return 'pages/CorrectlyPage';
    case 26: return 'pages/ColorsPage';
    case 100: return 'pages/MatchPairsThemePage';
    default: return 'pages/MemoryGridPage';
  }
}

function categoryName(cat: string): string {
  switch (cat) {
    case CAT_MEMORY:      return '记忆';
    case CAT_ATTENTION:   return '注意力';
    case CAT_SPEED:       return '速度';
    case CAT_PROBLEM:     return '问题解决';
    case CAT_FLEXIBILITY: return '灵活性';
    case CAT_IMAGINATION: return '想象力';
    default:              return '';
  }
}

// ─── Game data ─────────────────────────────────────────────────────────────────

const ALL_GAMES: GameEntry[] = [
  // Memory (记忆)
  { id: 100, name: '翻牌配对',   description: '经典翻牌找对 · 3主题×6难度',  category: CAT_MEMORY },
  { id: 1,  name: '记忆网格',   description: '记住网格中的位置',       category: CAT_MEMORY },
  { id: 2,  name: '六边形',     description: '六边形网格记忆游戏',     category: CAT_MEMORY },
  { id: 3,  name: '谁是新的',   description: '识别新出现的元素',       category: CAT_MEMORY },
  { id: 5,  name: '跟随路径',   description: '记住并跟随路径',         category: CAT_MEMORY },
  { id: 6,  name: '图像漩涡',   description: '图像记忆游戏',           category: CAT_MEMORY },
  { id: 8,  name: '找图片',     description: '找到之前看过的图片',     category: CAT_MEMORY },
  // Attention (注意力)
  { id: 4,  name: '旋转网格',   description: '记住网格位置，然后旋转', category: CAT_ATTENTION },
  { id: 7,  name: '抓住它们',   description: '快速抓住目标',           category: CAT_ATTENTION },
  // Speed (速度)
  { id: 24, name: '唯一的',     description: '找出唯一不同的元素',     category: CAT_SPEED },
  { id: 12, name: '全部相同',   description: '判断所有元素是否相同',   category: CAT_SPEED },
  { id: 13, name: '排序数字',   description: '快速排序数字',           category: CAT_SPEED },
  { id: 18, name: '找到全部',   description: '找到所有目标',           category: CAT_SPEED },
  { id: 22, name: '舒尔特表',   description: '按顺序点击数字',         category: CAT_SPEED },
  // Problem Solving (问题解决)
  { id: 25, name: '正确吗',     description: '判断数学等式是否正确',   category: CAT_PROBLEM },
  { id: 11, name: '更多更少',   description: '比较数字大小',           category: CAT_PROBLEM },
  { id: 16, name: '248',        description: '2048 类游戏',             category: CAT_PROBLEM },
  { id: 20, name: '对称',       description: '判断对称性',             category: CAT_PROBLEM },
  { id: 21, name: '激光',       description: '激光反射游戏',           category: CAT_PROBLEM },
  // Flexibility (灵活性)
  { id: 26, name: '颜色',       description: '判断颜色词与文字颜色是否匹配', category: CAT_FLEXIBILITY },
  { id: 14, name: '纸飞机',     description: '纸飞机方向游戏',         category: CAT_FLEXIBILITY },
  { id: 15, name: '像之前的吗', description: '判断是否与之前相同',     category: CAT_FLEXIBILITY },
  // Imagination (想象力)
  { id: 19, name: '数一数',     description: '数数游戏',               category: CAT_IMAGINATION },
  { id: 17, name: '金字塔',     description: '金字塔游戏',             category: CAT_IMAGINATION },
];

function filteredGames(selectedCat: string): GameEntry[] {
  if (selectedCat === CAT_ALL) return ALL_GAMES;
  const result: GameEntry[] = [];
  for (let i = 0; i < ALL_GAMES.length; i++) {
    if (ALL_GAMES[i].category === selectedCat) {
      result.push(ALL_GAMES[i]);
    }
  }
  return result;
}

// ─── Category chip ─────────────────────────────────────────────────────────────

@Component
struct CategoryChip {
  @Prop label: string = '';
  @Prop color: string = '#757575';
  @Prop selected: boolean = false;
  onSelect: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(13)
      .fontColor(this.selected ? '#FFFFFF' : this.color)
      .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Normal)
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .backgroundColor(this.selected ? this.color : '#F5F5F5')
      .borderRadius(20)
      .border({
        width: 1.5,
        color: this.selected ? this.color : '#E0E0E0'
      })
      .onClick(() => this.onSelect())
  }
}

// ─── Game card ─────────────────────────────────────────────────────────────────

@Component
struct GameCard {
  @Prop gameId: number = 0;
  @Prop gameName: string = '';
  @Prop gameDesc: string = '';
  @Prop category: string = '';
  onPlay: () => void = () => {};

  private isAvailable(): boolean {
    // All 23 games are implemented
    return true;
  }

  build() {
    Row({ space: 0 }) {
      // ── Colored icon box ─────────────────────────────
      Stack() {
        Column()
          .width(56)
          .height(56)
          .backgroundColor(categoryColor(this.category))
          .borderRadius(12)

        Text(categoryIcon(this.category))
          .fontSize(26)
      }
      .width(56)
      .height(56)
      .margin({ right: 16 })

      // ── Game info ────────────────────────────────────
      Column({ space: 3 }) {
        Text(this.gameName)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isAvailable() ? '#212121' : '#9E9E9E')
          .maxLines(1)

        Text(this.gameDesc)
          .fontSize(12)
          .fontColor('#757575')
          .maxLines(2)

        Text(categoryName(this.category))
          .fontSize(11)
          .fontColor(categoryColor(this.category))
          .fontWeight(FontWeight.Medium)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // ── Play / lock indicator ─────────────────────────
      if (this.isAvailable()) {
        Text('▶')
          .fontSize(22)
          .fontColor('#2196F3')
          .margin({ left: 8 })
          .onClick(() => this.onPlay())
      } else {
        Column({ space: 2 }) {
          Text('🔒')
            .fontSize(20)
            .fontColor('#BDBDBD')
          Text('即将推出')
            .fontSize(10)
            .fontColor('#BDBDBD')
        }
        .alignItems(HorizontalAlign.Center)
        .margin({ left: 8 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .shadow({ radius: 4, color: '#14000000', offsetX: 0, offsetY: 2 })
    .onClick(() => {
      if (this.isAvailable()) {
        this.onPlay();
      }
    })
  }
}

// ─── Sprint tab ────────────────────────────────────────────────────────────────

@Component
struct SprintTab {
  @State private selectedCat: string = CAT_ALL;
  private catScroller: Scroller = new Scroller();
  private listScroller: Scroller = new Scroller();

  build() {
    Column() {
      // ── Header ──────────────────────────────────────
      Column({ space: 4 }) {
        Text('Sprint 模式')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#212121')

        Text('选择一个游戏快速开始')
          .fontSize(14)
          .fontColor('#757575')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 16, bottom: 12 })

      // ── Category filter row ─────────────────────────
      Scroll(this.catScroller) {
        Row({ space: 8 }) {
          ForEach(
            CATEGORIES,
            (cat: CategoryEntry) => {
              CategoryChip({
                label: cat.name,
                color: cat.color,
                selected: this.selectedCat === cat.id,
                onSelect: () => {
                  this.selectedCat = cat.id;
                }
              })
            },
            (cat: CategoryEntry) => cat.id
          )
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      // ── Game list ───────────────────────────────────
      List({ space: 10, scroller: this.listScroller }) {
        ForEach(
          filteredGames(this.selectedCat),
          (game: GameEntry) => {
            ListItem() {
              GameCard({
                gameId: game.id,
                gameName: game.name,
                gameDesc: game.description,
                category: game.category,
                onPlay: () => {
                  const url = gamePageUrl(game.id);
                  router.pushUrl({ url });
                }
              })
              .padding({ left: 16, right: 16 })
            }
          },
          (game: GameEntry) => game.id.toString()
        )
        ListItem().height(16)
      }
      .layoutWeight(1)
      .width('100%')
      .divider({ strokeWidth: 0 })
      .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
  }
}

// ─── Placeholder tabs ──────────────────────────────────────────────────────────

@Component
struct PlaceholderTab {
  @Prop title: string = '';
  @Prop icon: string = '';

  build() {
    Column({ space: 16 }) {
      Text(this.icon)
        .fontSize(52)
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#424242')
      Text('功能开发中')
        .fontSize(14)
        .fontColor('#9E9E9E')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

// ─── Main page ─────────────────────────────────────────────────────────────────

@Entry
@Component
struct MainPage {
  @State private selectedTab: number = 0;
  @State private stars: number = 0;
  @State private coins: number = 0;

  // Tab definitions
  private tabIcons: string[] = ['▶', '🏋', '🏆', '👥', '☰'];
  private tabLabels: string[] = ['Sprint', 'Workout', 'Challenge', 'Online', '菜单'];

  build() {
    Column() {
      // ── Top bar ───────────────────────────────────────
      Row() {
        Text('Memory Games')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#212121')
          .layoutWeight(1)

        // Stars
        Row({ space: 4 }) {
          Text('★')
            .fontSize(18)
            .fontColor('#FFC107')
          Text(this.stars.toString())
            .fontSize(16)
            .fontColor('#212121')
        }
        .margin({ right: 16 })

        // Coins
        Row({ space: 4 }) {
          Text('💰')
            .fontSize(18)
          Text(this.coins.toString())
            .fontSize(16)
            .fontColor('#212121')
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 2, color: '#14000000', offsetX: 0, offsetY: 2 })
      .alignItems(VerticalAlign.Center)

      // ── Tab content ───────────────────────────────────
      Stack() {
        if (this.selectedTab === 0) {
          SprintTab()
        } else if (this.selectedTab === 1) {
          PlaceholderTab({ title: 'Workout', icon: '🏋' })
        } else if (this.selectedTab === 2) {
          PlaceholderTab({ title: 'Challenge', icon: '🏆' })
        } else if (this.selectedTab === 3) {
          PlaceholderTab({ title: 'Online', icon: '👥' })
        } else {
          PlaceholderTab({ title: '菜单', icon: '☰' })
        }
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#F5F5F5')

      // ── Bottom navigation bar ─────────────────────────
      Row() {
        ForEach(
          [0, 1, 2, 3, 4] as number[],
          (idx: number) => {
            Column({ space: 3 }) {
              Text(this.tabIcons[idx])
                .fontSize(this.selectedTab === idx ? 22 : 20)
                .fontColor(this.selectedTab === idx ? '#2196F3' : '#9E9E9E')

              Text(this.tabLabels[idx])
                .fontSize(11)
                .fontColor(this.selectedTab === idx ? '#2196F3' : '#9E9E9E')
                .fontWeight(this.selectedTab === idx ? FontWeight.Bold : FontWeight.Normal)
            }
            .layoutWeight(1)
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.selectedTab = idx;
            })
          },
          (idx: number) => `tab_${idx}`
        )
      }
      .width('100%')
      .height(60)
      .backgroundColor('#FFFFFF')
      .border({ width: { top: 1 }, color: '#E0E0E0' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
