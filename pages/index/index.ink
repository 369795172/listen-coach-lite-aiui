<!--
  听懂对方 · 沉浸式三区面板（todo 5，布局 SSOT 内联于此，替代独立设计文档）
  ====================================================================

  【整体】纵向三段式，面向 480x640 级窄幅眼镜 HUD；单绿 #40FF5E 族
  等宽 HUD 排版，黑底高对比、大字号、宽行距。

  【顶部状态条】常驻一行：
    - 采集指示点：state === 'listening' 时常显（恒亮，可见即知情；
      其余态暗显占位，避免布局跳动）——显隐裁决在 state.js isCapturing()
    - 四态中文标签：待机 idle / 聆听中 listening / 思考中 thinking /
      已完成 done（错误态显示「出错」）——文案裁决在 state.js STATUS_LABELS
    - 会话时钟：10:00 倒数（SESSION_LIMIT_MS=10 分钟，state.js 定义上限；
      页面每秒刷新显示，到 0 派发 TIMEOUT，收尾裁决仍归 state.js）
    - thinking 态仅有状态条脉冲动画（thinking-pulse），绝不渲染中间分析文本

  【渲染变体】由 state.js viewVariant() 裁决，markup 零判断：
    - empty   idle 空态：居中提示「说出对方的话，或按键开始」
    - zones   listening/thinking/done(未到期)：三区面板
              · listening/thinking 三区体仅显「——」占位（不上中间分析）
              · done(正常结算) 三区体显示 LLM 结果（对方要点/回应方向/一条原则）
    - expired done(expired=true) 到期态：10 分钟上限自动收尾说明
    - error   错误态：出错了 + 错误信息 + 重开提示

  【三区】标题逐字固定：对方要点 / 回应方向 / 一条原则
  （与 prompts/coach_system.md 三标记一一对应）。

  【三区排版预算与溢出防护（v0.1.3，商店二次驳回整改）】
    - .zone-body 20px/30px：420px 内容宽（480 − 左右 padding 30×2）≈ 21 字/行
    - 每区 .zone { flex:1; min-height:0; overflow:hidden }：三区 flex 等分
      不变，任何一区超长只在区内消化，不再把后序区挤出屏
    - v0.1.3 起不再依赖滚动：每区内容截断至 ZONE_MAX_CHARS（4 行 × 21 字
      = 84 字，prompt 契约输出 ≤80 字/区永不截断），超出加「…」续读指示；
      区体容器为普通 view（原 scroll-view 移除——真机滑动不可用正是本次
      驳回主因，渲染自持后滚动成为不必要能力）
    - 预算（480x640）：状态条 ≈40px + .zones padding 18px + 3 × (title 16 +
      gap 10 + body ≤120px) + fallback 标注 ~20px ≈ 572px ≤ 640px ✓
      ——三区 + 状态条常见情形一屏尽收，无需滑动即可读全

  【事件流】本页只渲染 + 派发：语音唤醒/按键 -> voice.enter()/forceSettle()；
  生命周期卸载/隐藏 -> voice.exit()；ASR/LLM/静默定时器全部在 voice.js，
  状态变化一律经 dispatch() 汇入 state.js transition()，markup/页面脚本
  零业务判断（todo 6 已接线；会话治理清单见 docs/session-governance.md）。

  【手势区分（v0.1.3，商店二次驳回整改）】镜腿触控板的滑动可能被上报为
  touch 和/或 key 事件；done 态阅读结果时的滑动绝不能误触新会话：
    - onTouchStart/onTouchEnd 记录起止坐标与时刻；tap = 时长 < 300ms 且
      位移 < 10px（任一轴；无坐标时退化为纯时长判定），其余（滑动/长按）
      只吞事件、不触发任何会话动作（保守取向：存疑不触发）
    - onKeyDown 在 GESTURE_DEDUPE_MS 窗内已有触控手势判定时以触控为准
      （tap 已由触控路径路由、滑动在此吞掉）；无触控遥测的纯按键保持
      原路由（listening=触发结算，其余=开新会话）
    - 会话动作唯一入口 handleTapActivation()；触控/按键双报的重复触发由
      voice.js enter()/settleNow() 幂等守卫兜底

  【v0.1.4 增量（第 4 次驳回整改：返回慢/无法滑动/arrow 误触）】
    - 段后静默 5s -> 3s（voice.js SILENCE_MS；宽限与空缓冲守卫独立兜底）
    - listening 态新增「说完轻触镜腿，立即生成」提示：tap 即结算成为
      显式主路径，审核员不干等静默窗
    - thinking 态渐进渲染升级：已定稿区（闭合标记出现）逐区上屏，
      未定稿区保持占位（parseZonesProgressive 判定，不上未验证文本）
    - done 态焦点翻区：明确滑动（≥SWIPE_MIN_DELTA）或方向键前向循环
      聚焦单区（null -> 要点 -> 方向 -> 原则 -> null），聚焦区放宽至
      FOCUS_MAX_CHARS=160（约 7 行），其余区收成标题行——「无滚动也能
      读全文」的第三条路；tap 在焦点态先退焦回总览，防阅读中误触重开
    - 方向键身份路由（keys.js 多形态提取）：done=翻区，其余态只吞，
      绝不映射为 enter 重开新会话（驳回主因之一）

  【todo 6 增量】done 态 zones.fallback 时渲染【本地规则】来源标注；
  ASR 错误态 errorMessage 承载「没听清，请再说一次」。
-->

<script setup>
import { initialState, transition, STATUS_LABELS, isCapturing, viewVariant, SESSION_LIMIT_MS } from './state.js';
import { createVoiceRuntime } from './voice.js';
import { extractKeyIdentity, isArrow, nextFocus } from './keys.js';

// 会话时钟显示格式：毫秒 -> mm:ss
function formatClock(ms) {
  const totalSeconds = Math.max(0, Math.ceil(ms / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  const mm = String(minutes).padStart(2, '0');
  const ss = String(seconds).padStart(2, '0');
  return mm + ':' + ss;
}

// —— v0.1.3 渲染预算：每区显示上限（≈4 行 × 21 字/行 @20px 字号/420px 宽）。
// prompt 契约输出 ≤80 字/区永不截断；超长（契约违例/流式中间态）截断加
// 「…」续读指示——三区常见情形一屏尽收，阅读结果不依赖滚动。
const ZONE_MAX_CHARS = 84;
// v0.1.4 焦点翻区：done 态滑动/方向键聚焦单区时，该区放宽至 ~7 行，
// 其余区收成标题行——「无滚动也能读全文」的第三条路（截断 ↔ 滚动之外）。
const FOCUS_MAX_CHARS = 160;
const ZONE_COUNT = 3;
// v0.1.4 滑动判定下限：位移 ≥ 该值且非 tap 判定为滑动（翻区手势）；
// 10px（TAP_MAX_DELTA）~ 24px 之间的模糊段按「非 tap 即吞」旧规则处理。
const SWIPE_MIN_DELTA = 24;

function clampZone(text) {
  const s = typeof text === 'string' ? text : '';
  if (s.length <= ZONE_MAX_CHARS) {
    return s;
  }
  return s.slice(0, ZONE_MAX_CHARS - 1) + '…';
}

function clampFocus(text) {
  const s = typeof text === 'string' ? text : '';
  if (s.length <= FOCUS_MAX_CHARS) {
    return s;
  }
  return s.slice(0, FOCUS_MAX_CHARS - 1) + '…';
}

// —— v0.1.3 手势区分（tap vs 滑动，商店二次驳回整改）——
// 镜腿触控板的滑动可能被上报为 touch 和/或 key 事件；done 态阅读结果时
// 的滑动绝不能误触新会话。判定规则（保守取向：存疑不触发）：
//   tap  = 时长 < TAP_MAX_MS 且位移 < TAP_MAX_DELTA（任一轴）
//   其他 = 滑动/长按，只吞事件，不触发任何会话动作
const TAP_MAX_MS = 300;
const TAP_MAX_DELTA = 10;
// 触控手势判定结果的有效窗：期内到达的 key 事件视为同一手势的重复上报
const GESTURE_DEDUPE_MS = 600;

// 从 touch 事件对象提取触点坐标（touches/changedTouches/detail/顶层，
// 多形态兼容——Ink 触控事件形状无公开文档可考，见 session-governance A5）
function touchPoint(event) {
  const e = event || {};
  const candidates = [];
  if (e.touches && e.touches[0]) {
    candidates.push(e.touches[0]);
  }
  if (e.changedTouches && e.changedTouches[0]) {
    candidates.push(e.changedTouches[0]);
  }
  if (e.detail && typeof e.detail.y === 'number') {
    candidates.push(e.detail);
  }
  candidates.push(e);
  for (let i = 0; i < candidates.length; i += 1) {
    const c = candidates[i] || {};
    if (typeof c.clientX === 'number' && typeof c.clientY === 'number') {
      return { x: c.clientX, y: c.clientY };
    }
    if (typeof c.pageX === 'number' && typeof c.pageY === 'number') {
      return { x: c.pageX, y: c.pageY };
    }
    if (typeof c.x === 'number' && typeof c.y === 'number') {
      return { x: c.x, y: c.y };
    }
  }
  return null;
}

export default {
  data: {
    hint: '说出对方的话，或按键开始',
    variant: 'empty',
    statusLabel: STATUS_LABELS.idle,
    capturing: false,
    clockText: formatClock(SESSION_LIMIT_MS),
    errorMessage: null,
    zonePoints: '——',
    zoneDirection: '——',
    zonePrinciple: '——'
  },

  onLoad() {
    // 会话机状态存实例字段（非渲染数据）；data 只放视图模型镜像
    this.machine = initialState();
    this.clockTimer = null;
    this.clockStartedAt = 0;
    // 结算期流式/兜底渲染状态（实例字段；viewModel 统一映射进 data）：
    // streamZones = 已定稿区渐进镜像（null = 未定稿保持占位）
    this.streamZones = { 对方要点: null, 回应方向: null, 一条原则: null };
    this.settleFallback = false;
    // v0.1.4 焦点翻区：done 态当前聚焦区索引（null = 三区总览）
    this.zoneFocused = null;
    // v0.1.3 手势追踪（实例字段，非渲染数据）：touchStart 记起手坐标/时刻；
    // lastGesture 记最近一次触控判定 {tap, at}，供 onKeyDown 去重
    this.touchStart = null;
    this.lastGesture = null;
    // 语音链路运行时：ASR/LLM/静默定时器/结算全部经 voice.js，
    // 状态变化仍经 dispatch() 汇入 state.js（markup/页面零业务判断）
    this.voice = createVoiceRuntime({
      dispatch: (event, payload) => this.dispatch(event, payload),
      getState: () => this.machine,
      onZonesDelta: (progress) => this.onZonesDelta(progress),
      onSettled: (result) => this.onSettled(result),
    });
    this.setData(this.viewModel(this.machine));
  },

  onUnload() {
    this.voiceExit();
    this.stopClock(false);
    this.machine = null;
    this.voice = null;
  },

  // 页面隐藏：按会话治理一律收口（资源全释放 + 状态机回 idle）
  onHide() {
    this.voiceExit();
  },

  // 沉浸式入口：语音唤醒开新会话（voice.js 建 LLM 会话并启 ASR）
  onVoiceWakeup(event) {
    if (event && typeof event.preventDefault === 'function') {
      try {
        event.preventDefault();
      } catch (_e) {}
    }
    this.voiceEnter();
  },

  // 沉浸式按键自接（v0.1.4：方向键永不重开——第 4 次驳回「arrow 事件被
  // 定义成 enter 自动开始下一轮」的修复；近窗内已有触控手势判定时以触控
  // 为准：tap 已由 onTouchEnd 路由、滑动在此吞掉；无触控遥测的纯按键中，
  // 方向键在 done 态翻区阅读、其余态只吞事件，enter/back 保持原路由）
  onKeyDown(event) {
    if (event && typeof event.preventDefault === 'function') {
      try {
        event.preventDefault();
      } catch (_e) {}
    }
    const gesture = this.lastGesture;
    if (gesture && Date.now() - gesture.at < GESTURE_DEDUPE_MS) {
      return; // 同一手势的重复上报：判定权在触控路径
    }
    const identity = extractKeyIdentity(event);
    if (isArrow(identity)) {
      if (this.machine && this.machine.state === 'done') {
        this.cycleZoneFocus();
      }
      return; // 方向键在 listening/thinking/idle 只吞不触发（绝不重开）
    }
    this.handleTapActivation();
  },

  // 触控起手：记录坐标与时刻（坐标缺失时仅记时刻，判定退化为纯时长）
  onTouchStart(event) {
    const point = touchPoint(event);
    this.touchStart = point
      ? { x: point.x, y: point.y, at: Date.now() }
      : { at: Date.now() };
  },

  // 触控抬手：tap（<300ms 且 <10px 位移）才允许触发会话动作；明确滑动
  // （位移 ≥ SWIPE_MIN_DELTA）在 done 态翻区阅读；其余（模糊段/长按）只吞
  // 事件。无起手记录（形态异常）时保守不触发。判定结果记入 lastGesture，
  // 供后续 key 事件去重（滑动若被重复上报为 key 也一并吞掉）
  onTouchEnd(event) {
    const start = this.touchStart;
    this.touchStart = null;
    if (!start) {
      return;
    }
    const end = touchPoint(event);
    const duration = Date.now() - start.at;
    let tap = duration < TAP_MAX_MS;
    let swipe = false;
    if (end && typeof start.x === 'number') {
      const dx = Math.abs(end.x - start.x);
      const dy = Math.abs(end.y - start.y);
      if (tap) {
        tap = Math.max(dx, dy) < TAP_MAX_DELTA;
      }
      swipe = !tap && Math.max(dx, dy) >= SWIPE_MIN_DELTA;
    }
    this.lastGesture = { tap: tap, at: Date.now() };
    if (tap) {
      this.handleTapActivation();
    } else if (swipe && this.machine && this.machine.state === 'done') {
      this.cycleZoneFocus();
    }
  },

  // tap 唯一动作面（触控 tap / 无遥测按键共用）：listening=触发结算；
  // done 且焦点翻区激活=先退出焦点回总览（防阅读中误触重开）；其余态
  // （idle/done(总览)/error）=开新会话。双路径重复触发由 voice.js
  // enter() 幂等守卫与 settleNow() phase 守卫兜底
  handleTapActivation() {
    if (this.machine && this.machine.state === 'listening') {
      this.voice.forceSettle();
    } else if (this.machine && this.machine.state === 'done' && this.zoneFocused !== null) {
      this.zoneFocused = null;
      this.setData(this.viewModel(this.machine));
    } else {
      this.voiceEnter();
    }
  },

  // v0.1.4 焦点翻区：done 态滑动/方向键前向循环聚焦（null -> 要点 -> 方向 -> 原则 -> null）
  cycleZoneFocus() {
    if (!this.machine || this.machine.state !== 'done') {
      return;
    }
    this.zoneFocused = nextFocus(this.zoneFocused, ZONE_COUNT);
    this.setData(this.viewModel(this.machine));
  },

  // 统一的会话进入/退出口（app.js onHide/onError 兜底也走这里）
  voiceEnter() {
    if (this.voice) {
      this.voice.enter();
    }
  },

  voiceExit() {
    if (this.voice) {
      this.voice.exit(); // 资源全释放 + dispatch('EXIT') -> idle
    }
  },

  // thinking 态已定稿区渐进渲染（v0.1.4）：只覆盖非 null 的已定稿区，
  // 未定稿区保持占位；定稿文本同样过 clampZone 守渲染预算
  onZonesDelta(progress) {
    if (this.machine && this.machine.state === 'thinking' && progress && typeof progress === 'object') {
      this.streamZones = {
        对方要点: typeof progress['对方要点'] === 'string' ? progress['对方要点'] : null,
        回应方向: typeof progress['回应方向'] === 'string' ? progress['回应方向'] : null,
        一条原则: typeof progress['一条原则'] === 'string' ? progress['一条原则'] : null,
      };
      this.setData(this.viewModel(this.machine));
    }
  },

  // 结算完成：记录兜底标注数据（【本地规则】标签由 zones.fallback 渲染）
  onSettled(result) {
    this.settleFallback = !!(result && result.fallback);
  },

  // 唯一事件汇入口：一切状态裁决归 state.js transition()
  dispatch(event, payload) {
    if (!this.machine) {
      return;
    }
    const next = transition(this.machine, event, payload);
    if (next.rejected) {
      // 非法事件在当前态被拒绝：忽略，不崩溃、不变迁
      return;
    }
    this.machine = next;
    if (event === 'ENTER' || event === 'EXIT') {
      // 新会话/退出：清空上一轮流式残文、兜底标注与焦点翻区
      this.streamZones = { 对方要点: null, 回应方向: null, 一条原则: null };
      this.settleFallback = false;
      this.zoneFocused = null;
    }
    this.setData(this.viewModel(next));
    this.syncClock(next);
  },

  // 状态机 -> 渲染数据（只做展示映射，状态判断全部查表 state.js）
  viewModel(m) {
    const variant = viewVariant(m);
    const filled = variant === 'zones' && m.zones !== null;
    const streaming = m.state === 'thinking';
    const focus = m.state === 'done' && this.zoneFocused !== null ? this.zoneFocused : null;
    const capFor = (idx) => (focus !== null && focus === idx ? clampFocus : clampZone);
    const collapsed = (idx) => focus !== null && focus !== idx;
    const titleClass = (idx) => {
      let cls = 'zone-title';
      if (focus !== null) {
        cls += idx === focus ? ' zone-focus' : ' zone-dim';
      }
      return cls;
    };
    const zoneText = (idx, finalText, streamText) => {
      if (filled) {
        return collapsed(idx) ? '' : capFor(idx)(finalText);
      }
      if (streaming && streamText) {
        return collapsed(idx) ? '' : clampZone(streamText);
      }
      return '——';
    };
    return {
      variant: variant,
      statusLabel: STATUS_LABELS[m.state] || m.state,
      capturing: isCapturing(m.state),
      errorMessage: m.errorMessage,
      // v0.1.3 渲染预算：每区 clampZone 截断 + 「…」续读指示，一屏尽收；
      // v0.1.4 焦点翻区：聚焦区放宽 FOCUS_MAX_CHARS，其余区收成标题行
      zonePoints: zoneText(0, m.zones ? m.zones.points : '', this.streamZones['对方要点']),
      zoneDirection: zoneText(1, m.zones ? m.zones.direction : '', this.streamZones['回应方向']),
      zonePrinciple: zoneText(2, m.zones ? m.zones.principle : '', this.streamZones['一条原则']),
      titleClass0: titleClass(0),
      titleClass1: titleClass(1),
      titleClass2: titleClass(2),
      listeningHint: m.state === 'listening',
      zonesFallback: filled ? this.settleFallback === true : false
    };
  },

  // 会话时钟随生命周期启停（倒计时到 0 派发 TIMEOUT；收尾裁决在 state.js）
  syncClock(m) {
    if (m.state === 'listening' || m.state === 'thinking') {
      this.startClock();
    } else if (m.state === 'idle') {
      this.stopClock(true);
    } else {
      this.stopClock(false);
    }
  },

  startClock() {
    if (this.clockTimer) {
      return;
    }
    this.clockStartedAt = Date.now();
    this.clockTimer = setInterval(() => this.tickClock(), 1000);
    this.tickClock();
  },

  stopClock(reset) {
    if (this.clockTimer) {
      clearInterval(this.clockTimer);
      this.clockTimer = null;
    }
    if (reset) {
      this.setData({ clockText: formatClock(SESSION_LIMIT_MS) });
    }
  },

  tickClock() {
    const remaining = Math.max(0, SESSION_LIMIT_MS - (Date.now() - this.clockStartedAt));
    this.setData({ clockText: formatClock(remaining) });
    if (remaining <= 0) {
      this.stopClock(false);
      if (this.voice) {
        this.voice.release(); // 到点先释放 ASR/LLM/定时器，再交状态机收尾
      }
      this.dispatch('TIMEOUT');
    }
  }
};
</script>

<page>
  <view class="panel">
    <!-- 顶部状态条：采集指示点（listening 常显）+ 状态标签 + 会话时钟 -->
    <view class="status-bar">
      <view class="status-left">
        <view class="capture-dot dot-{{capturing ? 'on' : 'off'}}"></view>
        <text class="status-label {{variant === 'thinking' ? 'thinking-pulse' : ''}}">{{statusLabel}}</text>
      </view>
      <text class="clock">{{clockText}}</text>
    </view>

    <!-- 空态（idle）：原始提示语 -->
    <view class="body" ink:if="{{variant === 'empty'}}">
      <text class="hint">{{hint}}</text>
    </view>

    <!-- 错误态 -->
    <view class="body" ink:if="{{variant === 'error'}}">
      <text class="state-title">出错了</text>
      <text class="state-detail">{{errorMessage || '请稍后再试'}}</text>
      <text class="hint">可再按一次键重新开始</text>
    </view>

    <!-- 到期态（done + expired）：10 分钟上限自动收尾 -->
    <view class="body" ink:if="{{variant === 'expired'}}">
      <text class="state-title">已到 10 分钟上限</text>
      <text class="state-detail">本次聆听已自动收尾</text>
      <text class="hint">按键开始下一轮</text>
    </view>

    <!-- 三区面板：listening/thinking 显占位（不上未定稿中间文本）；done 显结算 -->
    <!-- v0.1.3：区体为普通 view + 内容截断（ZONE_MAX_CHARS + 「…」），不再
         依赖滚动；v0.1.4：done 态滑动/方向键焦点翻区（聚焦区放宽、其余
         收成标题行）+ listening 态轻触提示（tap 即结算的主路径入口） -->
    <view class="zones" ink:if="{{variant === 'zones'}}">
      <text class="zone-source" ink:if="{{zonesFallback}}">【本地规则】</text>
      <view class="zone">
        <text class="{{titleClass0}}">对方要点</text>
        <view class="zone-scroll">
          <text class="zone-body">{{zonePoints}}</text>
        </view>
      </view>
      <view class="zone">
        <text class="{{titleClass1}}">回应方向</text>
        <view class="zone-scroll">
          <text class="zone-body">{{zoneDirection}}</text>
        </view>
      </view>
      <view class="zone">
        <text class="{{titleClass2}}">一条原则</text>
        <view class="zone-scroll">
          <text class="zone-body">{{zonePrinciple}}</text>
        </view>
      </view>
      <text class="listen-hint" ink:if="{{listeningHint}}">说完轻触镜腿，立即生成</text>
    </view>
  </view>
</page>

<style>
.panel {
  display: flex;
  flex-direction: column;
  height: 100vh;
  padding: 28px 30px;
  background-color: #000000;
  box-sizing: border-box;
}

/* —— 顶部状态条 —— */
.status-bar {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  padding-bottom: 18px;
  border-bottom: 1px solid rgba(64, 255, 94, 0.35);
}

.status-left {
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: 12px;
}

/* 采集指示点：listening 恒亮（常显），其余态暗显占位 */
.capture-dot {
  width: 12px;
  height: 12px;
  border-radius: 6px;
}

.dot-on {
  background-color: #40FF5E;
  box-shadow: 0 0 8px rgba(64, 255, 94, 0.85);
}

.dot-off {
  background-color: rgba(64, 255, 94, 0.18);
}

.status-label {
  font-size: 20px;
  font-weight: bold;
  color: #40FF5E;
  letter-spacing: 2px;
}

/* thinking 态唯一动画：状态条标签脉冲（无中间分析文本） */
.thinking-pulse {
  animation: thinking-blink 1.2s ease-in-out infinite;
}

@keyframes thinking-blink {
  0% {
    opacity: 1;
  }
  50% {
    opacity: 0.35;
  }
  100% {
    opacity: 1;
  }
}

.clock {
  font-size: 20px;
  font-weight: bold;
  color: rgba(64, 255, 94, 0.85);
}

/* —— 空态 / 错误态 / 到期态 共用主体 —— */
.body {
  display: flex;
  flex-direction: column;
  flex: 1;
  align-items: center;
  justify-content: center;
  gap: 14px;
}

.hint {
  width: 100%;
  text-align: center;
  font-size: 24px;
  line-height: 38px;
  color: #40FF5E;
}

.state-title {
  font-size: 30px;
  font-weight: bold;
  color: #40FF5E;
  text-align: center;
}

.state-detail {
  width: 100%;
  text-align: center;
  font-size: 20px;
  line-height: 32px;
  color: rgba(64, 255, 94, 0.8);
}

/* —— 三区面板 —— */
.zones {
  display: flex;
  flex-direction: column;
  flex: 1;
  padding-top: 18px;
}

/* v0.1.1 溢出防护：min-height:0 允许 flex 收缩小于内容高，overflow:hidden
   兜底剪裁——任何一区超长不再把兄弟区挤出屏（flex 等分不变） */
.zone {
  display: flex;
  flex-direction: column;
  flex: 1;
  gap: 10px;
  justify-content: flex-start;
  min-height: 0;
  overflow: hidden;
}

.zone-title {
  font-size: 16px;
  color: rgba(64, 255, 94, 0.55);
  letter-spacing: 4px;
}

/* v0.1.4 焦点翻区：聚焦区标题点亮，其余区标题压暗（正文已收空） */
.zone-focus {
  color: #40FF5E;
}

.zone-dim {
  color: rgba(64, 255, 94, 0.22);
}

/* v0.1.4 listening 态轻触提示：tap 即结算的主路径入口（第 4 次驳回
   「返回时间太慢」的感知层整改——审核员无需干等静默窗） */
.listen-hint {
  font-size: 16px;
  color: rgba(64, 255, 94, 0.5);
  letter-spacing: 2px;
  text-align: center;
  padding-top: 6px;
}

/* 兜底卡来源标注：LLM 不可用时的本地规则结算（zones.fallback 时渲染） */
.zone-source {
  font-size: 16px;
  color: rgba(64, 255, 94, 0.75);
  letter-spacing: 2px;
  padding-bottom: 4px;
}

/* 区体有界容器（v0.1.3 起为普通 view）：flex:1 + min-height:0 吃满区内
   剩余高度，overflow:hidden 兜底剪裁——内容超长由 clampZone 截断 +
   「…」续读指示在数据面消化，不依赖滚动 */
.zone-scroll {
  flex: 1;
  min-height: 0;
  overflow: hidden;
}

/* v0.1.1 字号下修（24px/38px → 20px/30px）：420px 内容宽 ≈ 21 字/行，
   prompt 契约上限 80 字 ≈ 4 行 ≈ 120px，三区 + 状态条稳进 640px */
.zone-body {
  font-size: 20px;
  line-height: 30px;
  font-weight: 600;
  color: #40FF5E;
}
</style>
