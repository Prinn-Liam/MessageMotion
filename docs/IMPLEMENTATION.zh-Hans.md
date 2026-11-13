# 实现接近 Messages 的聊天窗口

本文先于独立组件编写，作为实现与验收依据。目标是复现已获用户真机认可的气泡滚动与键盘联动。它描述一个使用公开 UIKit API 的实现，不声称还原 Apple 的内部代码。

## 1. 已认可的行为

- 慢拖有轻微拉伸、压缩；快划的形变更明显，不能快划反而更弱。
- 手指拖动和松手后的惯性滚动都带动气泡；减速时形变自然减小。
- 向上划时，参考点上方受压、下方拉开；向下反转。每个间距连续变化。
- 点住正在滑动的内容，页面立即停下，剩余间距迅速收拢，避免可见的反复振荡。
- 气泡间距有下限；快速滑动不因错误的行回收而露出空白。
- 从历史消息点输入框，真实滚过中间消息到最新位置；键盘收起时原有行与新进入视口的行一起移动，不出现两组气泡重叠、淡入或断层。
- 系统“减弱动态效果”生效，键盘显示时暂停气泡形变。

这里的真机认可来自原始实现。提取后的组件必须重新构建、运行和比较；不能把原版认可直接当作新项目已验收。

## 2. 分工与文件

`MotionChat` 是 SwiftUI 入口，接收带稳定 ID 的消息、一个气泡 View 构造器和一个输入栏 View。UIKit 控制器负责 UICollectionView、行测量、滚动和键盘。`MessageMotionLayout` 只负责静止几何、原生弹簧和最小间距。`MotionGeometry` 保存可测试的纯计算。业务状态、发送行为和视觉样式由调用方提供。

独立项目只使用 Apple 框架，最低 iOS18，Swift6；公开库不依赖原 App 的模型、主题、资源、后端或签名。示例使用内存消息，单独 bundleID。Swift Package 加独立示例的方式已由用户选定；没有把现有业务 App 一并开源。

## 3. 每个气泡的原生弹簧

每行保存静止几何与独立 `UIDynamicItem` 的连续位置；layout attributes 仅作为显示副本，不能把取整后的位置送回物理求解器。使用通用 `UIDynamicAnimator()`。本地探针观察到 layout attributes 作为物理对象时的像素量化，以及零长度 attachment 在锚点附近的漂移。现将 attachment 长度设为 `4 * max(contentHeight, viewportHeight, 1)`，锚点放在静止中心上方同等距离。竖直伸长仍等于气泡偏移；这个跨度是几何设置，不是输入阈值。原生 action 约束间距并刷新布局，自然暂停时精确归位，不添加死区、抖动阈值或定时强制归位。

起始设置：frequency4.5Hz、damping0.7、形变强度1.5、正常间距16pt、最小间距比例0.6、惯性阶段继续输入开启、距离除数1500。4.5Hz 是根据录像观察拟合的起始参数，不是测到的 Apple 私有常数。

这个开源版本保留已认可的独立弹簧路径。屏幕锚定实验、按偏移调整阻尼和按间距调整频率不进入核心，以免把废弃试验和有效机制混在一起。

每次原生滚动即将改变 bounds：

```text
delta = newBounds.minY - oldBounds.minY
weight = min(1, (abs(restingCenter.y-reference.y) + abs(restingCenter.x-reference.x)) / 1500)
animated.center.y += delta * weight * dragStrength
animator.updateItem(usingCurrentState: animated)
```

距离权重仍参考气泡静止中心，不使用移远后的 attachment 锚点。这是连续位置扰动，由原生弹簧随即恢复。没有按手势速度额外乘一个补偿系数。相同刷新条件下，每帧滚动距离随滚速增加，因此持续输入与滚速关联；实际结果还取决于原生积分器、刷新率、弹簧系数和行高，不能宣称一个对所有设备精确成立的解析比例。

拖动时参考点取手指在 collectionView 内容坐标里的位置。松手后记住最后的视口触点，惯性阶段每帧加上当前 bounds.origin，转换为内容坐标。惯性阶段只有原生 isDecelerating 且 bounds 在合法范围内才输入，越过边缘的橡皮筋回弹不输入。

滚动停止、重新触摸、新拖动、reset 均清理惯性标记。程序滚动、键盘高度变化和触摸补偿不能被误认为新的形变输入。

## 4. 最小间距与行回收

行高包含气泡底部的正常间距 padding，最后一行不添加 padding。可见边缘间距是：

```text
gap = next.frame.minY - previous.frame.maxY + normalGap
minimumGap = normalGap * minimumGapRatio
```

选择离参考触点最近的气泡作固定行，从它向下、向上投影：只把违反下限的行向外推，不移动固定行、不缩放气泡、不把全部间距改成常量。物理步中约束连续物理对象，并通知 animator；返回布局属性时再对副本投影作为渲染保护。比例只允许0到1。

查询可见行必须按**动画中的 frame**与查询 rect 相交，而不能先按静止 frame 筛选。示例为所有已加载消息准备物理状态，仅创建当前需要的 cell。这保证进入视口的形变行可用，成本为 O(n) 状态/查询；它不是未经验证的海量聊天历史虚拟化方案。

## 5. 点住：停止页面，允许间距收尾

使用一个不吞掉原生 pan 的触摸观察器：不延迟触摸、不取消子控件触摸，在 shouldReceive 阶段处理后返回 false。

1. 调用公开 `stopScrollingAndZooming()` 停止原生滚动；边缘回弹受 UIKit 自身规则约束。
2. 找到离触点最近的动画行，计算它相对静止中心的 lag。
3. 目标 contentOffset.y 为旧值减 lag，并钳制到合法内容范围。
4. 实际补偿记为 correction；所有动画行中心同时加 correction，再设置新的 contentOffset。两个变化在同一个无动画事务完成，所以屏幕坐标 `center-offset` 连续。
5. 根据静止中心及相同偏移锚点、长度重新建立独立 attachments，让相对间距继续恢复。

此路径会重建 animator 并清除旧速度。这是已认可基准的行为，不能在“整理代码”时悄悄换成另一种触摸模型。内容边缘钳制时，不能承诺被点住行完全固定。

## 6. 键盘：一个几何负责人

UIKit 的 keyboardLayoutGuide 把输入栏底部绑定到键盘顶部，消息列表底部绑定到输入栏顶部。仅这个组件忽略 SwiftUI keyboard avoidance，避免两套避让重复移动。interactive dismissal 保留原生跟手，keyboardDismissPadding 等于输入栏高度。

控制器区分：正在读历史、跟随最新、正在返回最新、用户正在拖动。最新消息为自己发送时跟随；收到新消息时，仅在原本接近底部才跟随。阅读位置用稳定消息 ID 和静止行相对视口的偏移保存。

点输入框需要回到底部时，视口布局使用键盘自己的动画时长与曲线；**contentOffset 不放进该 UIView 动画块**。单独使用 CADisplayLink，默认0.35秒三次缓出：

```text
p = clamp((targetTimestamp-startTime)/0.35, 0...1)
eased = 1-(1-p)^3
offset = startOffset + (latestOffsetNow-startOffset)*eased
```

每帧重读 latestOffset，因为键盘还在改变视口高度。这样中间的行真的经过布局和回收，不只显示起点/终点。距离超过6屏，先无动画定位到最后6屏，明确这是有意限制视觉行程。触摸、新拖动、离开窗口立即取消，完成才重新开启跟随最新。弱代理持有 displayLink 回调目标，避免循环引用。

高度变化不会改变行的静止几何，所以 `shouldInvalidateLayout(forBoundsChange:)` **仅因宽度变化返回 true**。键盘高度变化不能触发 UICollectionView 带淡入/位移的 bounds 过渡。appearing/disappearing attributes 使用行自己的位置与完整不透明度；willDisplay 完成新 cell 的无动画布局，并清理它的首次布局动画。这是基准中的修复，使用复杂自带动画的气泡内容时需要重新评估。

缓存按消息值、宽度、是否末行、正常间距、Dynamic Type 和调用方 layoutRevision 失效。高度/宽度改变、消息追加、编辑、空列表都需要明确处理，避免将缓存失效误当成新的滚动输入。

## 7. 验证与证据等级

- 单元测试：配置归一化、输入方向/限幅、惯性与边缘门控、最小间距/固定行/幂等性、触摸补偿连续性、跟随策略、返回最新插值和取消。
- UIKit 集成：真实 collectionView 动画属性、进入视口的行、惯性输入、触摸补偿，使用原生 animator；不以手写弹簧求解器代替它。
- 运行路径：慢拖、快划、双向快划点住、历史点输入框、键盘交互收起、原地收起、追加消息、空列表、长列表与减弱动态效果。
- 打包验证：从导出目录/zip独立构建，不能引用父工程、本机绝对路径、用户签名、私有素材或录像。
- 真机对比：独立示例安装后由用户检查手感；自动测试不能证明和 Messages 像素级一致。

原始笔记里的参考观察：慢拖约±5pt、快划约−13/+19到29pt、点住恢复约0.17秒、压缩下限约正常的0.62。它们来自特定屏幕录像，原始背景、行高、静止间距和采样位置不同，不作为所有示例界面的硬性数值断言。新示例没有重新完成与 Messages 的逐帧录像比较前，不标记“完美复刻”或宣称 Apple 使用本算法。

## 8. 来源

- [objc.io: UICollectionView + UIKit Dynamics](https://www.objc.io/issues/5-ios7/collection-views-and-uidynamics/)：公开的 collectionView 独立弹簧思路。
- [BouncyLayout](https://github.com/roberthein/BouncyLayout)：已有相关开源布局；本项目重点是完整聊天/键盘集成、可解释参数和可运行示例，不宣称首次提出弹簧列表。
- [Apple: stopScrollingAndZooming](https://developer.apple.com/documentation/uikit/uiscrollview/stopscrollingandzooming())：公开停止滚动 API，iOS17.4起可用；边缘回弹有例外。
- 原项目用户提供的 Messages/沙盒录像测量与 Claude 的实现笔记：参数拟合和问题定位来源；不随开源包分发私人录屏或业务代码。
