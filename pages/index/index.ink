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

  【三区排版预算与溢出防护（v0.1.1，修复三区挤下屏）】
    - .zone-body 20px/30px（v0.1.0 曾 24px/38px）：420px 内容宽（480 −
      左右 padding 30×2）≈ 21 字/行，prompt 契约上限 80 字 ≈ 4 行 ≈ 120px
    - 每区 .zone { flex:1; min-height:0; overflow:hidden }：三区 flex 等分
      不变，任何一区超长只在区内消化，不再把后序区挤出屏
    - .zone-body 内容包 scroll-view（scroll-y，flex:1 + min-height:0 有界）：
      超长内容区内心滚动，内容不丢失
    - 预算（480x640）：状态条 ≈40px + .zones padding 18px + 3 × (title 16 +
      gap 10 + body ≤105) ≈ 449px ≤ 640px ✓（含 4 行满载 body 120px/区 与
      fallback 标注 ~20px 的最坏情形 ≈ 532px，仍 ✓）

  【事件流】本页只渲染 + 派发：语音唤醒/按键 -> voice.enter()/forceSettle()；
  生命周期卸载/隐藏 -> voice.exit()；ASR/LLM/静默定时器全部在 voice.js，
  状态变化一律经 dispatch() 汇入 state.js transition()，markup/页面脚本
  零业务判断（todo 6 已接线；会话治理清单见 docs/session-governance.md）。

  【todo 6 增量】thinking 态「回应方向」区可显流式增量（结算触发后，
  仅方向区、其余两区保持占位）；done 态 zones.fallback 时渲染
  【本地规则】来源标注；ASR 错误态 errorMessage 承载「没听清，请再说一次」。
-->

<script setup>
import { initialState, transition, STATUS_LABELS, isCapturing, viewVariant, SESSION_LIMIT_MS } from './state.js';
import { createVoiceRuntime } from './voice.js';

// 会话时钟显示格式：毫秒 -> mm:ss
function formatClock(ms) {
  const totalSeconds = Math.max(0, Math.ceil(ms / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  const mm = String(minutes).padStart(2, '0');
  const ss = String(seconds).padStart(2, '0');
  return mm + ':' + ss;
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
    // 结算期流式/兜底渲染状态（实例字段；viewModel 统一映射进 data）
    this.streamDirection = '';
    this.settleFallback = false;
    // 语音链路运行时：ASR/LLM/静默定时器/结算全部经 voice.js，
    // 状态变化仍经 dispatch() 汇入 state.js（markup/页面零业务判断）
    this.voice = createVoiceRuntime({
      dispatch: (event, payload) => this.dispatch(event, payload),
      getState: () => this.machine,
      onDirectionDelta: (partial) => this.onDirectionDelta(partial),
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

  // 沉浸式按键自接：listening=触发结算；其余态=开新会话
  onKeyDown(event) {
    if (event && typeof event.preventDefault === 'function') {
      try {
        event.preventDefault();
      } catch (_e) {}
    }
    if (this.machine && this.machine.state === 'listening') {
      this.voice.forceSettle();
    } else {
      this.voiceEnter();
    }
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

  // thinking 态「回应方向」流式渐进渲染：只更新方向区（结算前零中间文本）
  onDirectionDelta(partialText) {
    if (this.machine && this.machine.state === 'thinking' && typeof partialText === 'string') {
      this.streamDirection = partialText;
      this.setData({ zoneDirection: partialText || '——' });
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
      // 新会话/退出：清空上一轮流式残文与兜底标注
      this.streamDirection = '';
      this.settleFallback = false;
    }
    this.setData(this.viewModel(next));
    this.syncClock(next);
  },

  // 状态机 -> 渲染数据（只做展示映射，状态判断全部查表 state.js）
  viewModel(m) {
    const variant = viewVariant(m);
    const filled = variant === 'zones' && m.zones !== null;
    // thinking 态方向区可显流式增量（结算触发后；其余 listening 态恒占位）
    const streaming = m.state === 'thinking' && this.streamDirection;
    return {
      variant: variant,
      statusLabel: STATUS_LABELS[m.state] || m.state,
      capturing: isCapturing(m.state),
      errorMessage: m.errorMessage,
      zonePoints: filled ? m.zones.points : '——',
      zoneDirection: filled ? m.zones.direction : (streaming || '——'),
      zonePrinciple: filled ? m.zones.principle : '——',
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

    <!-- 三区面板：listening/thinking 显占位（不上中间分析）；done 显结算 -->
    <!-- v0.1.1：区体包 scroll-view（区内心滚动），任何一区超长不挤压兄弟区 -->
    <view class="zones" ink:if="{{variant === 'zones'}}">
      <text class="zone-source" ink:if="{{zonesFallback}}">【本地规则】</text>
      <view class="zone">
        <text class="zone-title">对方要点</text>
        <scroll-view class="zone-scroll" scroll-y="true">
          <text class="zone-body">{{zonePoints}}</text>
        </scroll-view>
      </view>
      <view class="zone">
        <text class="zone-title">回应方向</text>
        <scroll-view class="zone-scroll" scroll-y="true">
          <text class="zone-body">{{zoneDirection}}</text>
        </scroll-view>
      </view>
      <view class="zone">
        <text class="zone-title">一条原则</text>
        <scroll-view class="zone-scroll" scroll-y="true">
          <text class="zone-body">{{zonePrinciple}}</text>
        </scroll-view>
      </view>
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

/* 兜底卡来源标注：LLM 不可用时的本地规则结算（zones.fallback 时渲染） */
.zone-source {
  font-size: 16px;
  color: rgba(64, 255, 94, 0.75);
  letter-spacing: 2px;
  padding-bottom: 4px;
}

/* 区体有界滚动容器：flex:1 + min-height:0 吃满区内剩余高度，
   内容超高时区内心滚动（scroll-y），内容不丢失 */
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
