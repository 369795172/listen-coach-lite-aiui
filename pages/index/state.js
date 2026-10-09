// 听懂对方 · 会话状态机（纯函数模块，零副作用）
//
// 契约：本模块是页面唯一的状态决策层。页面（index.ink）只渲染视图模型，
// 并把一切输入（语音唤醒 / 按键 / ASR 回调 / LLM 回调 / 会话时钟）作为
// 事件派发给 transition()；markup 与页面脚本不做任何状态判断。
//
// 纯度：无 I/O、无定时器、无模块级可变状态；transition 从不改写输入，
// 一律返回新对象（相同输入必产生深相等输出，可直接 require/import 复测）。
//
// 状态集（5）：'idle' | 'listening' | 'thinking' | 'done' | 'error'
//   - done 携带 expired:boolean：TIMEOUT 到期收尾 = true，正常结算 = false。
//   - error 为独立状态（设计取舍：错误时整页切错误卡渲染，恢复靠 ENTER
//     重开或 EXIT 回待机，不与 done 的 expired 标志混用）。
//
// 事件集（9）：ENTER | EXIT | ASR_START | ASR_END | LLM_START | LLM_DONE
//             | LLM_FAIL | TIMEOUT | ERROR
//
// 合法转移表（下方 TRANSITIONS 为唯一权威声明，transition() 严格照此执行）：
//   idle      + ENTER     -> listening   开新会话（缓冲/zones/错误全清）
//   idle      + EXIT      -> idle        幂等复位（无会话可退，同样清缓冲）
//   idle      + ERROR     -> error
//   listening + EXIT      -> idle        取消：ASR 缓冲清空
//   listening + ASR_START -> listening   采集开始确认（幂等；可携带新段追加）
//   listening + ASR_END   -> thinking    采集结束进结算（可携带最终段追加）
//   listening + TIMEOUT   -> done        expired=true（10 分钟到点收尾）
//   listening + ERROR     -> error
//   thinking  + EXIT      -> idle        取消：ASR 缓冲清空
//   thinking  + LLM_START -> thinking    LLM 请求派发（幂等）
//   thinking  + LLM_DONE  -> done        expired=false，payload.zones 存入
//   thinking  + LLM_FAIL  -> error       payload.message 存入 errorMessage
//   thinking  + TIMEOUT   -> done        expired=true（结算中超时同样收尾）
//   thinking  + ERROR     -> error
//   done      + ENTER     -> listening   直接开始下一轮
//   done      + EXIT      -> idle
//   done      + ERROR     -> error
//   error     + ENTER     -> listening   重试开新会话
//   error     + EXIT      -> idle
//   error     + ERROR     -> error       幂等（errorMessage 以最新为准）
//   其余（状态×事件）组合一律非法，包括但不限于：thinking 中 ENTER、
//   idle 中 ASR_START/ASR_END/LLM_*、listening 中 LLM_START/LLM_DONE、
//   done/error 中 TIMEOUT、done 中 ASR_*/LLM_*。
//
// 拒绝契约：非法或未知事件不抛异常，返回
//   { ...原状态快照（深拷贝、原样）, rejected: true, reason: '<EVENT> in <STATE>' }
//   result.state 保持进入事件时的状态名（即「未变迁」）；合法转移的返回
//   结果不含 rejected 字段，调用方以 result.rejected === true 判定拒绝。
//
// 状态对象形状（closed shape，transition 输出恒为此形）：
//   { state, expired, segments, zones, errorMessage }
//   segments: string[]                                ASR 文本缓冲（EXIT/ENTER 清空）
//   zones: null | {points, direction, principle}      LLM 三区结算结果
//   errorMessage: null | string                       错误态说明
//
// payload 契约（缺省容错，多余字段忽略，永不触发异常）：
//   ENTER     {}                        忽略一切携带，重置为全新会话
//   EXIT      {}
//   ASR_START { segments?: string[] }   追加 ASR 段
//   ASR_END   { segments?: string[] }   追加最终段
//   LLM_START {}
//   LLM_DONE  { zones: {points, direction, principle} }
//   LLM_FAIL  { message?: string }
//   TIMEOUT   {}
//   ERROR     { message?: string }

export const STATES = ['idle', 'listening', 'thinking', 'done', 'error'];

export const EVENTS = [
  'ENTER',
  'EXIT',
  'ASR_START',
  'ASR_END',
  'LLM_START',
  'LLM_DONE',
  'LLM_FAIL',
  'TIMEOUT',
  'ERROR',
];

// 单会话 10 分钟上限（页面时钟据此倒数，到 0 派发 TIMEOUT）
export const SESSION_LIMIT_MS = 10 * 60 * 1000;

// 状态条四态 + 错误态的中文标签（页面渲染的唯一文案来源）
export const STATUS_LABELS = Object.freeze({
  idle: '待机',
  listening: '聆听中',
  thinking: '思考中',
  done: '已完成',
  error: '出错',
});

// 采集指示常显规则：listening 态恒亮（可见即知情），其余态暗显
export function isCapturing(stateName) {
  return stateName === 'listening';
}

// 渲染变体裁决：empty（空态）/ zones（三区面板）/ expired（到期态）/ error（错误态）
export function viewVariant(s) {
  if (s.state === 'idle') return 'empty';
  if (s.state === 'error') return 'error';
  if (s.state === 'done') return s.expired ? 'expired' : 'zones';
  return 'zones';
}

// 唯一权威转移表：TRANSITIONS[当前态][事件] = 目标态；缺键 = 非法
export const TRANSITIONS = Object.freeze({
  idle: { ENTER: 'listening', EXIT: 'idle', ERROR: 'error' },
  listening: {
    EXIT: 'idle',
    ASR_START: 'listening',
    ASR_END: 'thinking',
    TIMEOUT: 'done',
    ERROR: 'error',
  },
  thinking: {
    EXIT: 'idle',
    LLM_START: 'thinking',
    LLM_DONE: 'done',
    LLM_FAIL: 'error',
    TIMEOUT: 'done',
    ERROR: 'error',
  },
  done: { ENTER: 'listening', EXIT: 'idle', ERROR: 'error' },
  error: { ENTER: 'listening', EXIT: 'idle', ERROR: 'error' },
});

export function initialState() {
  return {
    state: 'idle',
    expired: false,
    segments: [],
    zones: null,
    errorMessage: null,
  };
}

// 状态迁移唯一入口。合法 -> 新状态对象（无 rejected 字段）；
// 非法/未知 -> {...原状态快照, rejected: true, reason}，绝不抛异常。
export function transition(state, event, payload) {
  const from = state && typeof state.state === 'string' ? state.state : String(state && state.state);
  const table = TRANSITIONS[from];
  const target = table ? table[event] : undefined;
  if (!table || target === undefined) {
    return { ...copyState(state), rejected: true, reason: `${String(event)} in ${from}` };
  }

  const p = payload || {};
  switch (event) {
    case 'ENTER':
      return { ...initialState(), state: 'listening' };
    case 'EXIT':
      return initialState();
    case 'ASR_START':
    case 'ASR_END':
      return { ...copyState(state), state: target, segments: appendSegments(state.segments, p.segments) };
    case 'LLM_START':
      return { ...copyState(state), state: target };
    case 'LLM_DONE':
      return { ...copyState(state), state: 'done', expired: false, zones: copyZones(p.zones) };
    case 'LLM_FAIL':
    case 'ERROR':
      return {
        ...copyState(state),
        state: 'error',
        errorMessage: typeof p.message === 'string' && p.message ? p.message : null,
      };
    case 'TIMEOUT':
      return { ...copyState(state), state: 'done', expired: true, zones: null };
    default:
      // 表内出现未实现事件：按非法处理（防御，正常不可达）
      return { ...copyState(state), rejected: true, reason: `${String(event)} in ${from}` };
  }
}

// —— 以下均为模块内私有纯 helper，不做导出 ——

function copyState(state) {
  if (!state || typeof state !== 'object') {
    return initialState();
  }
  return {
    state: typeof state.state === 'string' ? state.state : 'idle',
    expired: !!state.expired,
    segments: Array.isArray(state.segments) ? state.segments.slice() : [],
    zones: state.zones && typeof state.zones === 'object' ? { ...state.zones } : null,
    errorMessage: typeof state.errorMessage === 'string' ? state.errorMessage : null,
  };
}

function appendSegments(current, incoming) {
  const base = Array.isArray(current) ? current : [];
  if (!Array.isArray(incoming) || incoming.length === 0) {
    return base.slice();
  }
  const clean = incoming.filter((seg) => typeof seg === 'string');
  return [...base, ...clean];
}

function copyZones(zones) {
  if (!zones || typeof zones !== 'object') {
    return null;
  }
  return {
    points: typeof zones.points === 'string' ? zones.points : '',
    direction: typeof zones.direction === 'string' ? zones.direction : '',
    principle: typeof zones.principle === 'string' ? zones.principle : '',
  };
}
