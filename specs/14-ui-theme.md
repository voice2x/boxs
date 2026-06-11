# UI 主题与视觉风格

## 一、设计原则

```
三个关键词：

  紧凑 ── 一屏内展示更多有效信息，减少滚动和翻页
  精致 ── 自定义每一个组件，不用系统默认样式
  高密度 ── 信息紧凑排列，但不杂乱（区别于时光序的拥挤）

反面教材：
  ❌ Material Design 默认样式 — 间距大、圆角大、浪费空间
  ❌ Cupertino 风格 — iOS 原生列表太松散
  ❌ 时光序 — 紧凑但杂乱，视觉噪音大
  ❌ 随手记 — 紧凑但丑，像 Excel

目标：像 Tweetbot / Bear / Things 3 那样
      紧凑、克制、精致，每个像素都有意义
```

---

## 二、色彩体系

### 色板

```
亮色模式（Light）：

  背景
  ├─ #F8F7F4  页面底色（暖米白，不是纯白）
  ├─ #FFFFFF  卡片/弹窗（纯白，和底色拉开层次）
  └─ #EFEDE8  分割线 / 边框

  主色
  └─ #D4573E  铁锈红（比之前 #E8725C 更沉稳，不跳）
               紧凑布局下颜色面积大，需要更低饱和度避免刺眼

  文字
  ├─ #1D1D1B  主文字
  ├─ #6E6E6A  次要文字
  └─ #A3A39E  占位/提示

  语义
  ├─ #3B9B6E  收入/正向（暗绿，和主色拉开距离）
  ├─ #C94C4C  支出/超支（暗红，克制不刺眼）
  ├─ #4A8FC7  信息/链接
  └─ #C4883A  警告/待办

暗色模式（Dark）：

  背景
  ├─ #141413  页面底色
  ├─ #1E1E1C  卡片
  ├─ #282826  弹窗/弹出层
  └─ #333331  分割线

  主色
  └─ #E0725C  比亮色模式亮一档

  文字
  ├─ #EAE9E5  主文字
  ├─ #989893  次要文字
  └─ #626260  占位

  语义
  ├─ #5DB88A  收入
  ├─ #E07A6A  支出
  ├─ #6DA8D6  信息
  └─ #D9A25A  警告
```

### 色彩使用比例

```
一个页面内的颜色分布：

  95%  中性色（背景 + 文字）
   4%  主色（按钮、高亮、活跃态）
   1%  语义色（收入绿、支出红）

紧凑布局下主色不能多用。铁锈红只在关键操作点出现：
  - 语音按钮
  - 打卡完成勾
  - 确认按钮
其余大面积用中性色，让主色成为视觉锚点。
```

---

## 三、排版体系

### 字体

```
系统默认字体：
  iOS:    SF Pro Text / SF Pro Display

数字字体（金额）：
  iOS:    SF Mono（等宽，数字对齐）

金额等宽是关键：
  ¥1,250.50
  ¥   35.00    ← 小数点对齐
  ¥  128.00
```

### 字号

```
紧凑版字号（比常规版小 1-2dp）：

  ┌───────────────┬──────┬────────────┬──────────┐
  │ 用途           │ 字号 │ 字重        │ 行高     │
  ├───────────────┼──────┼────────────┼──────────┤
  │ 页面标题       │ 20   │ SemiBold   │ 26       │
  │ 区块标题       │ 15   │ SemiBold   │ 20       │
  │ 卡片主文字     │ 14   │ Medium     │ 18       │
  │ 卡片次要文字   │ 12   │ Regular    │ 16       │
  │ 标签/徽章     │ 10   │ Medium     │ 14       │
  │ 金额（大）     │ 26   │ Bold       │ 30       │
  │ 金额（列表）   │ 15   │ SemiBold   │ 20       │
  └───────────────┴──────┴────────────┴──────────┘
```

### 间距

```
紧凑版间距（4dp 网格，全面收紧）：

  页面左右边距  16dp（不是 20dp）
  卡片内边距    12dp（不是 16dp）
  列表项间距    0dp（用 1px 分割线，不用间距）
  区块间距      16dp（不是 24dp）
  元素间紧凑    4dp（不是 8dp）

  核心思路：间距省出来的空间，给内容。
```

---

## 四、自定义组件体系

不使用系统默认组件样式。每个控件都从头定制。

### 1. 横向滑动概览卡片（OverviewCard）

```
不用系统 Card / ScrollView 默认样式，自定义横向滑动卡片：

← 横向滑动概览卡片 →
┌──────────┐ ┌──────────┐ ┌──────────┐
│ 📋 待办  │ │ 💰 账单  │ │ 🏃 打卡  │
│ 今日 3/5 │ │ 本月     │ │ 今日 3/5 │
│ 已完成3  │ │ ¥3,850   │ │ 🏃✓📖✓💧│
│ ■■■□□   │ │ ↑12%     │ │          │
└──────────┘ └──────────┘ └──────────┘

卡片尺寸：
  宽度   屏幕宽 1/3（约 120dp）或自适应
  高度   80dp
  圆角   10dp
  内边距 12dp
  卡片间距 8dp

每张卡片结构：
  第一行：emoji + 标题（10dp Medium）
  第二行：主数据（15dp SemiBold）
  第三行：辅助信息（10dp Regular）
  第四行：进度条或标签（可选）

卡片背景色 #FFFFFF（亮色）/ #1E1E1C（暗色）
使用 ScrollView(.horizontal) + LazyHStack 实现
带 paging 行为，一次滑动一张或多张
```

### 2. 自定义列表项（CompactListItem）

```
不用系统 List 默认行，自定义更紧凑的行：

┌──────────────────────────────────────┐
│ 🍜  午饭                  -¥35.50   │  ← 行高 44dp
│ 餐饮 · 沙县小吃         12:30        │
├──────────────────────────────────────┤  ← 1px 分割线 #EFEDE8
│ 🚕  打车                  -¥28.00   │
│ 交通                      09:15      │
├──────────────────────────────────────┤
│ 📝  周五开会                    ○     │
│ 待办 · 提醒 15:00              │     │
└──────────────────────────────────────┘

自定义参数：
  高度       自适应（最小 44dp）
  左侧 emoji  20dp（不是 32dp）
  左边距     16dp
  右边距     16dp
  行内间距   2dp（主文字和副文字之间）
  分割线     左偏移 52dp（emoji 右对齐）
  金额       右对齐，负号前置

对比系统 List Row：
  系统默认高度 56dp → 自定义 44dp（每行省 12dp）
  一屏显示 14 条 → 18 条
```

### 3. 自定义分割线（AppDivider）

```
紧凑分割线，左侧留出 emoji 空间：

  ─────────────────────────  ← 1px #EFEDE8
  ↑                          ↑
  左偏移 52dp（emoji 右侧）  右边距 16dp

系统默认 Divider 全宽，自定义左偏移对齐文字区域，
视觉上更干净。
```

### 4. 自定义标签（Tag）

```
不用系统 Chip，自定义更小的标签：

┌──────┐  ┌──────┐  ┌───────┐  ┌──────┐
│ 餐饮  │  │ 交通  │  │ 购物   │  │ +3   │
└──────┘  └──────┘  └───────┘  └──────┘

高度 22dp，内边距 4×8dp，圆角 6dp
字号 10dp，Medium 字重
背景色 #EFEDE8（暖灰），文字 #6E6E6A
选中态：背景 #D4573E 15% 透明度，文字 #D4573E
```

### 5. 自定义按钮样式（ActionButton）

```
不用系统 Button 默认样式，统一自定义：

主按钮（确认/提交）：
  高度 36dp（系统默认 40dp）
  圆角 8dp
  背景 #D4573E，文字 #FFFFFF
  内边距 8×16dp

次按钮（取消/修改）：
  高度 36dp
  圆角 8dp
  背景 transparent，边框 1px #D4573E，文字 #D4573E

文字按钮（更多/详情）：
  无背景无边框
  文字 #4A8FC7 12dp
  无内边距，右箭头 →
```

### 6. 浮动语音按钮（VoiceButton）

```
不嵌入任何 Bar，独立浮动在页面底部正中：

       ┌─────┐
       │ 🎤  │  ← 40dp 圆形按钮
       └─────┘
          ↑
    页面底部正中，距底 20dp
    不遮挡列表内容，列表底部留 60dp padding

样式：
  默认态：圆形 40dp，背景 #D4573E，图标 #FFFFFF
  按住态：放大到 46dp，外圈脉冲波纹
  波纹：opacity 0.4→0, scale 1.0→1.6, 1.2s 循环

脉冲动画（唯一持续的动画）：
  状态：按住时
  效果：外圈波纹扩散
  时长：1.2s
  参数：opacity 0.4→0, scale 1.0→1.6
```

### 7. 自定义半弹窗（HalfSheet）

```
不用系统 .sheet 全屏弹出，自定义半屏弹窗：

┌──────────────────────────────────────┐
│ ──  ← 4dp × 32dp 灰色把手           │
│                                      │
│  已识别                              │
│  ┌────────────────────────────────┐  │
│  │ 🍜 午饭                -35.50 │  │  ← 可编辑卡片
│  │ 餐饮 · 沙县小吃               │  │
│  │ 🎤 语音                       │  │
│  └────────────────────────────────┘  │
│                                      │
│  ┌──────────┐    ┌──────────┐       │
│  │   修改    │    │  确认 ✓  │       │
│  └──────────┘    └──────────┘       │
│                                      │
└──────────────────────────────────────┘

特点：
  顶部圆角 16dp
  把手代替关闭按钮（省空间）
  内容区紧贴把手
  按钮区紧贴底边
  无多余间距
```

### 8. 自定义输入框

```
不用系统 TextField 默认样式，自定义更紧凑：

┌──────────────────────────────────────┐
│ 备注  ┌────────────────────────┐     │
│       │ 午饭                   │     │
│       └────────────────────────┘     │
│ 金额  ┌───┐                          │
│       │35 │  .  ┌──┐                 │
│       └───┘      │50│                │
│                  └──┘                 │
└──────────────────────────────────────┘

金额输入特殊处理：
  整数部分大号（20dp Bold）
  小数部分中号（14dp Regular）
  小数点固定显示
  不用系统键盘，自定义数字键盘
```

---

## 五、页面布局

### 首页

```
┌──────────────────────────────────┐
│ 6/10 周二                    ⚙  │  顶栏 40dp
├──────────────────────────────────┤
│ ← 横向滑动概览卡片 →              │  概览卡片 80dp
│ ┌──────────┐┌──────────┐┌──────┐│
│ │ 📋 待办  ││ 💰 账单  ││🏃 打卡││
│ │ 今日 3/5 ││ 本月     ││3/5   ││
│ │ 已完成3  ││ ¥3,850   ││🏃✓📖 ││
│ │ ■■■□□   ││ ↑12%     ││      ││
│ └──────────┘└──────────┘└──────┘│
├──────────────────────────────────┤
│                                  │
│ 🍜 午饭                -35.50 │  列表每行 44dp
│ 餐饮 · 沙县          12:30    │
│ ───────────────────────────── │  分割线
│ 🚕 打车                -28.00 │
│ 交通                  09:15   │
│ ───────────────────────────── │
│ 📝 周五开会                  │
│ 待办 · 15:00             ○    │
│ ───────────────────────────── │
│ 💧 喝水                     ✓ │
│ 习惯 · 今天第 8 杯            │
│ ───────────────────────────── │
│ 🛒 日用品              -56.00 │
│ 购物 · 盒马          08:30   │
│ ───────────────────────────── │
│ 📖 阅读 30 页               ✓ │
│ 习惯 · 已连续 12 天           │
│                                  │
│              🎤                  │  浮动语音按钮
│         （距底 20dp）             │  不在底栏中
│                                  │  列表底部留 60dp
└──────────────────────────────────┘

总高度计算：
  顶栏 40 + 概览卡片 80 + 列表 6×44 + 底部间距 60 = 444dp
  iPhone 14 高度 844dp
  一屏可显示 9 条记录，比常规布局多 3-4 条

布局结构：
  - 顶栏固定在顶部
  - 概览卡片区域：水平滑动
  - 记录列表：垂直滚动，占满剩余空间
  - 语音按钮：Z 轴浮于底部正中，不影响列表滚动
```

### 记账详情页

```
┌──────────────────────────────────┐
│ ←  记账详情                     │  顶栏 40dp
├──────────────────────────────────┤
│                                  │
│        - ¥ 35.50                 │  金额 36dp
│                                  │
├──────────────────────────────────┤
│ 分类  🍜 餐饮                   │  每行 36dp
│ 日期  2025-06-10 周二           │  共 5 行
│ 商家  沙县小吃                   │  180dp
│ 来源  🎤 语音                   │
│ 备注  午饭                       │
├──────────────────────────────────┤
│ 操作记录                         │
│ 12:30 创建（语音）              │
│ 12:31 修改金额 ¥38 → ¥35.50    │
├──────────────────────────────────┤
│ ┌────────┐  ┌────────┐  ┌────┐ │
│ │  编辑  │  │  删除  │  │撤销│ │  操作栏
│ └────────┘  └────────┘  └────┘ │
└──────────────────────────────────┘
```

### 统计页

```
┌──────────────────────────────────┐
│ 6月                 < 2025 >    │  月份切换 36dp
├──────────────────────────────────┤
│ 支出 ¥3,850  收入 ¥12,000      │  总览 28dp
│ 预算 ¥5,000 剩余 ¥1,150        │  预算进度 20dp
│ ████████████░░░░░░ 77%          │  进度条 8dp
├──────────────────────────────────┤
│ 分类排行                         │
│ 🍜 餐饮   ¥1,250  ████████ 32% │  每行 28dp
│ 🚕 交通   ¥680   █████ 18%    │  紧凑列表
│ 🛒 购物   ¥520   ███ 14%     │
│ 🏠 居住   ¥480   ███ 12%     │
│ 👕 服饰   ¥320   ██ 8%      │
│ 📱 数码   ¥280   ██ 7%      │
│ 其他      ¥320           9% │
├──────────────────────────────────┤
│ 日支出趋势                       │
│ 30│    ╱╲                       │  迷你图表
│ 20│  ╱   ╲╱╲                    │  80dp
│ 10│╱       ╲                    │
│  0├──┬──┬──┬──                  │
│    1  8  15 22                  │
└──────────────────────────────────┘
```

---

## 六、SwiftUI 实现要点

### 不用的系统组件样式

```
完全弃用默认样式：
  ❌ NavigationStack 默认标题栏（自定义顶栏）
  ❌ List 默认 row height（系统高度 56dp → 自定义 44dp）
  ❌ Card 默认 elevation/shadow（自定义无阴影卡片）
  ❌ Chip（高度太高 → 自定义 Tag 22dp）
  ❌ Button 默认样式（高度太高 40dp → 自定义 36dp）
  ❌ TextField 默认样式 → 完全自定义
  ❌ .sheet 全屏弹出 → 自定义半屏弹窗
  ❌ TabView 底栏 → 无底栏，语音按钮独立浮动

使用的基础能力（不弃用）：
  ✅ Canvas（自定义绘制）
  ✅ ScrollView + LazyVStack / LazyHStack（列表滚动）
  ✅ Gesture（手势识别：TapGesture, DragGesture, LongPressGesture）
  ✅ withAnimation / @Animation（动画）
  ✅ GeometryReader（屏幕适配）
  ✅ ViewThatFits / Layout（响应式布局）
  ✅ @Environment / EnvironmentKey（主题注入）
  ✅ .preferredColorScheme（暗色模式切换）
```

### 自定义 Theme 定义

```swift
// Core/Theme/AppColors.swift

import SwiftUI

// ── 通过 EnvironmentKey 注入主题色 ──

struct AppColorsKey: EnvironmentKey {
    static let defaultValue: AppColors = .light
}

extension EnvironmentValues {
    var appColors: AppColors {
        get { self[AppColorsKey.self] }
        set { self[AppColorsKey.self] = newValue }
    }
}

// ── 主题色定义 ──

struct AppColors {
    let background: Color
    let surface: Color
    let border: Color
    let primary: Color
    let textPrimary: Color
    let textSecondary: Color
    let textHint: Color
    let income: Color
    let expense: Color
    let info: Color
    let warning: Color

    // ── 亮色 ──
    static let light = AppColors(
        background:    Color(hex: "F8F7F4"),
        surface:       Color(hex: "FFFFFF"),
        border:        Color(hex: "EFEDE8"),
        primary:       Color(hex: "D4573E"),
        textPrimary:   Color(hex: "1D1D1B"),
        textSecondary: Color(hex: "6E6E6A"),
        textHint:      Color(hex: "A3A39E"),
        income:        Color(hex: "3B9B6E"),
        expense:       Color(hex: "C94C4C"),
        info:          Color(hex: "4A8FC7"),
        warning:       Color(hex: "C4883A")
    )

    // ── 暗色 ──
    static let dark = AppColors(
        background:    Color(hex: "141413"),
        surface:       Color(hex: "1E1E1C"),
        border:        Color(hex: "333331"),
        primary:       Color(hex: "E0725C"),
        textPrimary:   Color(hex: "EAE9E5"),
        textSecondary: Color(hex: "989893"),
        textHint:      Color(hex: "626260"),
        income:        Color(hex: "5DB88A"),
        expense:       Color(hex: "E07A6A"),
        info:          Color(hex: "6DA8D6"),
        warning:       Color(hex: "D9A25A")
    )
}

// ── Color hex 便捷初始化 ──

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
```

```swift
// Core/Theme/AppSpacing.swift

/// 紧凑间距体系
enum S {
    static let page: CGFloat    = 16    // 页面边距
    static let card: CGFloat    = 12    // 卡片内边距
    static let section: CGFloat = 16    // 区块间距
    static let item: CGFloat    = 4     // 元素间紧凑
    static let row: CGFloat     = 8     // 行间距
    static let tag: CGFloat     = 4     // 标签内距
}
```

```swift
// Core/Theme/AppRadius.swift

enum R {
    static let card: CGFloat        = 10
    static let button: CGFloat      = 8
    static let tag: CGFloat         = 6
    static let bottomSheet: CGFloat = 16
    static let avatar: CGFloat      = 20
}
```

```swift
// Core/Theme/AppSize.swift

enum Sz {
    // 高度
    static let topBar: CGFloat     = 40
    static let listItem: CGFloat   = 44
    static let compactRow: CGFloat = 36
    static let tag: CGFloat        = 22
    static let button: CGFloat     = 36

    // 图标
    static let emoji: CGFloat      = 20
    static let icon: CGFloat       = 18
    static let iconSmall: CGFloat  = 14

    // 语音按钮
    static let voiceIdle: CGFloat   = 40
    static let voiceActive: CGFloat = 46
}
```

### 自定义组件示例

```swift
// Widgets/CompactListItem.swift

import SwiftUI

struct CompactListItem: View {
    let emoji: String
    let title: String
    let subtitle: String?
    let trailing: String?
    let trailingColor: Color?
    let onTap: (() -> Void)?

    @Environment(\.appColors) private var c

    init(
        emoji: String,
        title: String,
        subtitle: String? = nil,
        trailing: String? = nil,
        trailingColor: Color? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.trailingColor = trailingColor
        self.onTap = onTap
    }

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(alignment: .center, spacing: 10) {
                // emoji
                Text(emoji)
                    .font(.system(size: Sz.emoji))

                // 主内容
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(c.textPrimary)
                        .lineSpacing(1.3)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(c.textSecondary)
                            .lineSpacing(1.3)
                    }
                }

                Spacer()

                // 右侧
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(trailingColor ?? c.textPrimary)
                }
            }
            .padding(.horizontal, S.page)
            .padding(.vertical, 10)
            .frame(minHeight: Sz.listItem, alignment: .center)
        }
        .buttonStyle(.plain)
    }
}
```

```swift
// Widgets/AppDivider.swift

import SwiftUI

/// 紧凑分割线，左侧留出 emoji 空间
struct AppDivider: View {
    @Environment(\.appColors) private var c

    var body: some View {
        Rectangle()
            .fill(c.border)
            .frame(height: 0.5)
            .padding(.leading, S.page + Sz.emoji + 10) // 左偏到 emoji 右侧
            .padding(.trailing, S.page)
    }
}
```

```swift
// Widgets/OverviewCard.swift

import SwiftUI

/// 横向滑动概览卡片
struct OverviewCard: View {
    let emoji: String
    let title: String
    let mainValue: String
    let subtitle: String
    let progress: CGFloat?   // 0...1，可选进度条

    @Environment(\.appColors) private var c

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 第一行：emoji + 标题
            HStack(spacing: 4) {
                Text(emoji)
                    .font(.system(size: Sz.emoji))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(c.textSecondary)
            }

            // 第二行：主数据
            Text(mainValue)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.textPrimary)
                .monospacedDigit()

            // 第三行：辅助信息
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(c.textSecondary)
                .lineLimit(1)

            // 第四行：进度条（可选）
            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(c.border)
                        Rectangle()
                            .fill(c.primary)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 4)
                .clipShape(Capsule())
            }
        }
        .padding(S.card)
        .frame(width: 120, height: 80, alignment: .leading)
        .background(c.surface)
        .clipShape(RoundedRectangle(cornerRadius: R.card))
    }
}
```

```swift
// Widgets/TagView.swift

import SwiftUI

/// 自定义标签
struct TagView: View {
    let text: String
    let isSelected: Bool

    @Environment(\.appColors) private var c

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(isSelected ? c.primary : c.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, S.tag)
            .background(
                isSelected
                    ? c.primary.opacity(0.15)
                    : Color(hex: "EFEDE8")
            )
            .clipShape(RoundedRectangle(cornerRadius: R.tag))
            .frame(height: Sz.tag)
    }
}
```

```swift
// Widgets/ActionButtonStyle.swift

import SwiftUI

/// 自定义按钮样式
struct ActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case text
    }

    let kind: Kind
    @Environment(\.appColors) private var c

    func makeBody(configuration: Configuration) -> some View {
        switch kind {
        case .primary:
            configuration.label
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(height: Sz.button)
                .background(c.primary)
                .clipShape(RoundedRectangle(cornerRadius: R.button))

        case .secondary:
            configuration.label
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(c.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(height: Sz.button)
                .overlay(
                    RoundedRectangle(cornerRadius: R.button)
                        .stroke(c.primary, lineWidth: 1)
                )

        case .text:
            HStack(spacing: 2) {
                configuration.label
                    .font(.system(size: 12))
                    .foregroundStyle(c.info)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(c.info)
            }
        }
    }
}
```

```swift
// Widgets/VoiceButton.swift

import SwiftUI

/// 浮动语音按钮
struct VoiceButton: View {
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var isPressed = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.4

    @Environment(\.appColors) private var c

    var body: some View {
        ZStack {
            // 脉冲波纹
            if isPressed {
                Circle()
                    .stroke(c.primary.opacity(pulseOpacity), lineWidth: 2)
                    .frame(width: Sz.voiceIdle * pulseScale, height: Sz.voiceIdle * pulseScale)
                    .onAppear { startPulse() }
                    .onDisappear { stopPulse() }
            }

            // 按钮本体
            Button(action: onTap) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(
                        width: isPressed ? Sz.voiceActive : Sz.voiceIdle,
                        height: isPressed ? Sz.voiceActive : Sz.voiceIdle
                    )
                    .background(c.primary)
                    .clipShape(Circle())
            }
            .simultaneousGesture(
                LongPressGesture()
                    .onEnded { _ in onLongPress() }
            )
            .onLongPressGesture(
                minimumDuration: .infinity,
                pressing: { pressing in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isPressed = pressing
                    }
                },
                perform: {}
            )
        }
        .padding(.bottom, 20)
    }

    private func startPulse() {
        withAnimation(
            .easeOut(duration: 1.2)
            .repeatForever(autoreverses: false)
        ) {
            pulseScale = 1.6
            pulseOpacity = 0
        }
    }

    private func stopPulse() {
        pulseScale = 1.0
        pulseOpacity = 0.4
    }
}
```

```swift
// Widgets/HalfSheet.swift

import SwiftUI

/// 自定义半屏弹窗
struct HalfSheet<Content: View>: View {
    @Binding var isPresented: Bool
    let content: Content

    @Environment(\.appColors) private var c

    init(isPresented: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._isPresented = isPresented
        self.content = content()
    }

    var body: some View {
        if isPresented {
            ZStack {
                // 遮罩
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { isPresented = false }

                // 弹窗内容
                VStack(spacing: 0) {
                    // 把手
                    Capsule()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 32, height: 4)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    content
                }
                .background(c.surface)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: R.bottomSheet,
                        topTrailingRadius: R.bottomSheet
                    )
                )
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
                .transition(.move(edge: .bottom))
            }
            .animation(.easeOut(duration: 0.25), value: isPresented)
        }
    }
}
```

---

## 七、紧凑但不压抑的技巧

```
如何做到紧凑但不难受：

1. 用分割线不用间距
   列表项之间 0dp 间距 + 1px 分割线
   比 8dp 间距省空间，视觉更干净

2. 字号降 1-2dp，行高压缩
   14dp 字号 + 1.3 行高（默认 1.4）
   视觉上几乎无差别，但每行省 1-2dp

3. 去掉所有不必要的装饰
   无阴影、无圆角过大、无多余图标
   每个元素都有功能目的

4. 信息内联而非换行
   "餐饮 · 沙县小吃 · 12:30"  ← 一行搞定
   不写成三行

5. 合并页面区域
   概览用横向滑动卡片（80dp 高度）
   三张卡片并排，滑动浏览，不占纵向空间

6. 无底栏，语音按钮浮动
   不用 TabView 底栏（省 48dp）
   语音按钮独立浮动在底部正中
   列表可滚到底，底部留 60dp padding 避让按钮

7. 空间换信息密度
   一屏 9 条记录 vs 常规 5-6 条
   用户减少 40% 的滚动操作
```

---

## 八、动画

```
紧凑界面下动画更要克制，每个动画必须有用：

1. 语音按钮脉冲（唯一持续的动画）
   状态：按住时
   效果：外圈波纹扩散
   时长：1.2s
   参数：opacity 0.4→0, scale 1.0→1.6

2. 打卡切换
   状态：点击打卡
   效果：背景色灰→主色，弹性缩放
   时长：200ms
   曲线：.easeOut

3. 新记录插入
   状态：AI 识别完插入列表
   效果：从上方滑入
   时长：180ms
   曲线：.easeOut

仅此 3 个。其余一律静态。
```

---

## 九、总结

| 维度 | 选择 | 理由 |
|------|------|------|
| **布局** | 高密度紧凑 | 一屏多看 40% 内容 |
| **组件** | 100% 自定义 | 系统组件间距过大 |
| **主色** | 铁锈红 #D4573E | 紧凑布局下调饱和度，不刺眼 |
| **间距** | 4dp 网格，全面收紧 | 16dp 边距 / 12dp 内距 / 0dp 列表间距 |
| **列表行高** | 44dp（vs 系统 56dp） | 一屏多显示 3-4 条 |
| **导航** | 无底栏，语音按钮浮动 | 省掉 48dp 底栏，内容区最大化 |
| **概览** | 横向滑动卡片 | 80dp 高度内展示待办/账单/打卡 |
| **分割** | 1px 线（不用间距） | 紧凑但有序 |
| **信息密度** | 单行内联（· 分隔） | 一行说清，不换行 |
| **字号** | 降 1-2dp | 视觉无差别，空间有差别 |
| **阴影** | 无 | 1px 底边框代替 |
| **圆角** | 8-10dp | 紧凑下小圆角更精致 |
