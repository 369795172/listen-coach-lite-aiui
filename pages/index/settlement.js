// 听懂对方 · 结算纯函数模块（todo 6，零副作用，与 state.js 同风格）
//
// 契约：本模块只做确定性的文本结算——把 LLM 应答文本与 ASR 段落缓冲
// 归位为三区渲染数据结构。无 I/O、无定时器、无模块级可变状态；
// 对任意畸形输入（非字符串 / 缺标记 / 空段）一律返回合法结构，绝不抛异常。
//
// 三标记（与 prompts/coach_system.md 逐字一致，解析按标记原样切分）：
//   【对方要点】 / 【回应方向】 / 【一条原则】
//
// 解析失败规则（计划 todo 6「解析失败整段进回应方向区」）：
//   三标记未全部出现，或任一标记区正文为空 => 视为解析失败——
//   整段 LLM 文本进「回应方向」，其余两区由 settle() 以中性占位符兜底
//   （settle 会用 ASR 摘要与尾段提取覆盖其中两区，见 settle 注释）。
//
// 输出结构（UI 消费面，zone 键与三标记正文一一对应）：
//   { zones: {对方要点, 回应方向, 一条原则}, fallback: boolean,
//     markersFound: boolean, label: null | '【本地规则】' }

export const MARKERS = Object.freeze(['【对方要点】', '【回应方向】', '【一条原则】']);
export const ZONE_KEYS = Object.freeze(['对方要点', '回应方向', '一条原则']);

// 解析失败时两兜底区的中性占位文案
export const PARSE_PLACEHOLDER = '（未识别）';

// 本地规则兜底卡的来源标注（UI 在 zones.fallback 时渲染此标签）
export const FALLBACK_LABEL = '【本地规则】';

// 摘要与解析失败正文的安全上限（HUD 可读性；模型约束每段 ≤80 字，
// 解析失败时模型约束已失守，用确定性截断兜底）
export const SUMMARY_CAP = 240;
export const TAIL_CAP = 80;

// normalizeText(x)：非字符串输入归一为 ''；字符串原样（不去空白）
function normalizeText(value) {
  return typeof value === 'string' ? value : '';
}

// capText(text, limit)：超过 limit 截断到 limit-1 字并追加 '…'（总长恰为 limit）
function capText(text, limit) {
  if (text.length <= limit) {
    return text;
  }
  return text.slice(0, limit - 1) + '…';
}

// parseZones(llmText) -> { zones, markersFound }
//
// 三标记全部出现且各区正文非空 => markersFound=true，按标记切分
// （标记乱序也按各自标记归位，正文取本标记后到下一标记前的片段）。
// 否则 => markersFound=false，整段文本（截断）进「回应方向」，
// 其余两区为 PARSE_PLACEHOLDER。永不抛异常。
export function parseZones(llmText) {
  const text = normalizeText(llmText).trim();
  const found = MARKERS.map((marker) => text.indexOf(marker));
  const allPresent = found.every((idx) => idx >= 0);

  if (allPresent) {
    const ordered = MARKERS
      .map((marker, i) => ({ marker, zone: ZONE_KEYS[i], idx: found[i] }))
      .sort((a, b) => a.idx - b.idx);
    const zones = {};
    let complete = true;
    for (let i = 0; i < ordered.length; i += 1) {
      const item = ordered[i];
      const bodyStart = item.idx + item.marker.length;
      const bodyEnd = i + 1 < ordered.length ? ordered[i + 1].idx : text.length;
      const body = text.slice(bodyStart, bodyEnd).trim();
      if (!body) {
        complete = false;
        break;
      }
      zones[item.zone] = body;
    }
    if (complete) {
      for (const zone of ZONE_KEYS) {
        zones[zone] = capText(zones[zone], SUMMARY_CAP);
      }
      return { zones, markersFound: true };
    }
  }

  // 解析失败：整段（截断）进回应方向，其余两区中性占位
  return {
    zones: {
      对方要点: PARSE_PLACEHOLDER,
      回应方向: capText(text, SUMMARY_CAP),
      一条原则: PARSE_PLACEHOLDER,
    },
    markersFound: false,
  };
}

// summarizeSegments(segments) -> string
//
// ASR 段落的朴素确定性合并（无 LLM）：滤非字符串、去首尾空白、
// 丢空段、按原顺序拼接，超 SUMMARY_CAP 截断。空输入 => ''。
// 仅在模型输出无可用标记时充当「对方要点」区的来源；标记解析成功时
// 三区措辞一律以 LLM 路径为准（本函数不参与）。
export function summarizeSegments(segments) {
  if (!Array.isArray(segments)) {
    return '';
  }
  const merged = segments
    .filter((seg) => typeof seg === 'string')
    .map((seg) => seg.trim())
    .filter((seg) => seg.length > 0)
    .join('');
  return capText(merged, SUMMARY_CAP);
}

// extractTailLine(llmText) -> string（计划 todo 6「一条原则=尾段提取」）
//
// 取 LLM 文本最后一个非空行，超 TAIL_CAP 截断；无内容 => ''。
// 仅用于解析失败路径的「一条原则」区兜底。
export function extractTailLine(llmText) {
  const text = normalizeText(llmText).trim();
  if (!text) {
    return '';
  }
  const lines = text.split(/\r?\n/);
  for (let i = lines.length - 1; i >= 0; i -= 1) {
    const line = lines[i].trim();
    if (line) {
      return capText(line, TAIL_CAP);
    }
  }
  return '';
}

// buildFallbackCard(sample) -> 兜底卡结构
//
// 从 samples.json 单组样例的 expected 三区构造本地规则兜底卡：
//   { zones: {对方要点, 回应方向, 一条原则}, fallback: true,
//     label: '【本地规则】', markersFound: false }
// 样例畸形（缺 expected / 非字符串区）时对应区用 PARSE_PLACEHOLDER。
// 永不抛异常。
export function buildFallbackCard(sample) {
  const expected = sample && typeof sample === 'object' ? sample.expected : null;
  const zones = {};
  for (const zone of ZONE_KEYS) {
    const value = expected && typeof expected === 'object' ? expected[zone] : null;
    zones[zone] = typeof value === 'string' && value.trim() ? value : PARSE_PLACEHOLDER;
  }
  return { zones, fallback: true, label: FALLBACK_LABEL, markersFound: false };
}

// longestCommonSubstringLen(a, b)：最长公共子串长度（确定性 DP，短文本 O(n*m)）
function longestCommonSubstringLen(a, b) {
  const n = a.length;
  const m = b.length;
  if (n === 0 || m === 0) {
    return 0;
  }
  let prev = new Array(m + 1).fill(0);
  let best = 0;
  for (let i = 1; i <= n; i += 1) {
    const curr = new Array(m + 1).fill(0);
    for (let j = 1; j <= m; j += 1) {
      if (a.charCodeAt(i - 1) === b.charCodeAt(j - 1)) {
        curr[j] = prev[j - 1] + 1;
        if (curr[j] > best) {
          best = curr[j];
        }
      }
    }
    prev = curr;
  }
  return best;
}

// pickClosestSample(samples, asrText) -> sample | null
//
// 本地规则兜底卡的场景匹配器（确定性）：取 input 与 ASR 文本
// 最长公共子串最长的样例；并列时按数组顺序取先出现者。
// 无可用样例 => null。
export function pickClosestSample(samples, asrText) {
  if (!Array.isArray(samples) || samples.length === 0) {
    return null;
  }
  const text = normalizeText(asrText);
  let best = null;
  let bestLen = -1;
  for (const sample of samples) {
    const input = sample && typeof sample === 'object' ? normalizeText(sample.input) : '';
    const len = longestCommonSubstringLen(text, input);
    if (len > bestLen) {
      bestLen = len;
      best = sample;
    }
  }
  return best;
}

// settle(asrSegments, llmText, opts?) -> 结算渲染结构（UI 消费面）
//
//   opts.fallbackCard  传入 buildFallbackCard 结果 => 走本地规则兜底卡
//                      （LLM 不可用路径由 voice.js 构造后传入）。
//
// 标记解析成功：三区 = LLM 标记分区（markersFound=true，措辞以 LLM 为准）。
// 标记解析失败：整段 LLM 文本进「回应方向」；「对方要点」= ASR 段落摘要
// 合并（无段则中性占位）；「一条原则」= 尾段提取（无内容则中性占位）。
export function settle(asrSegments, llmText, opts) {
  const options = opts && typeof opts === 'object' ? opts : {};

  if (options.fallbackCard && typeof options.fallbackCard === 'object') {
    const card = options.fallbackCard;
    const zones = {};
    for (const zone of ZONE_KEYS) {
      const value = card.zones && typeof card.zones === 'object' ? card.zones[zone] : null;
      zones[zone] = typeof value === 'string' && value ? value : PARSE_PLACEHOLDER;
    }
    return { zones, fallback: true, label: FALLBACK_LABEL, markersFound: false };
  }

  const parsed = parseZones(llmText);
  if (parsed.markersFound) {
    return { zones: parsed.zones, fallback: false, label: null, markersFound: true };
  }

  const summary = summarizeSegments(asrSegments);
  const tail = extractTailLine(llmText);
  return {
    zones: {
      对方要点: summary || PARSE_PLACEHOLDER,
      回应方向: parsed.zones.回应方向,
      一条原则: tail || PARSE_PLACEHOLDER,
    },
    fallback: false,
    label: null,
    markersFound: false,
  };
}
