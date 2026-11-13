// 听懂对方 · 按键身份纯函数模块（v0.1.4，第 4 次驳回整改）
//
// 契约：本模块只做两件确定性判定，供 index.ink 按键路由使用——
//   extractKeyIdentity(event) 从多形态键事件中提取身份；
//   nextFocus(current, zoneCount) 计算焦点翻区的下一个索引。
// 零 I/O、零模块级状态、畸形输入不抛异常。
//
// 背景（docs/session-governance.md A5）：Ink 键事件形状无公开文档可考，
// 第 4 次驳回意见「arrow事件会被定义成enter自动开始下一轮」证明真机至少
// 存在上/下方向键事件。提取采用多形态轮询（key/code/keyCode/detail.* /
// 顶层字段），认不出的形状返回 null——调用方退回既有路由，绝不猜身份。

// 身份归一表：字符串键名（大小写不敏感）与数字 keyCode 混查
const KEY_ALIASES = {
  arrowup: 'up', up: 'up', 38: 'up',
  arrowdown: 'down', down: 'down', 40: 'down',
  arrowleft: 'left', left: 'left', 37: 'left',
  arrowright: 'right', right: 'right', 39: 'right',
  enter: 'enter', 13: 'enter',
  back: 'back', escape: 'back', 27: 'back',
};

const KNOWN_IDENTITIES = Object.freeze(['up', 'down', 'left', 'right', 'enter', 'back']);

export function isArrow(identity) {
  return identity === 'up' || identity === 'down' || identity === 'left' || identity === 'right';
}

// extractKeyIdentity(event) -> 'up'|'down'|'left'|'right'|'enter'|'back'|null
export function extractKeyIdentity(event) {
  const e = event && typeof event === 'object' ? event : {};
  const detail = e.detail && typeof e.detail === 'object' ? e.detail : {};
  const candidates = [e.key, e.code, e.keyCode, e.keyName, detail.key, detail.code, detail.keyCode, detail.keyName];
  for (const candidate of candidates) {
    if (typeof candidate === 'number' && Number.isInteger(candidate)) {
      const mapped = KEY_ALIASES[candidate];
      if (mapped) {
        return mapped;
      }
    } else if (typeof candidate === 'string' && candidate) {
      const mapped = KEY_ALIASES[candidate.toLowerCase()];
      if (mapped) {
        return mapped;
      }
    }
  }
  return null;
}

// nextFocus(current, zoneCount) -> number|null
// 焦点前向循环：null -> 0 -> 1 -> ... -> zoneCount-1 -> null。
// current 非法（越界/类型不符）按 null 处理；zoneCount <= 0 恒 null。
export function nextFocus(current, zoneCount) {
  if (!Number.isInteger(zoneCount) || zoneCount <= 0) {
    return null;
  }
  const validCurrent = Number.isInteger(current) && current >= 0 && current < zoneCount ? current : null;
  if (validCurrent === null) {
    return 0;
  }
  const next = validCurrent + 1;
  return next < zoneCount ? next : null;
}

export { KNOWN_IDENTITIES };
