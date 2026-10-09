// 听懂对方 · 应用生命周期（todo 6 扩展：onHide/onError 一律路由到
// 会话收口——计划 guardrail「EXIT/onHide/onError 一律 destroy() 并停 ASR
// 清缓冲」。页面钩子不触发或页面未到达时由这里兜底；实际资源释放与
// 状态机迁移都在页面侧 voice.js/state.js，本文件只做委托。）

// 取栈顶页面并委托其会话收口；无页面框架 API / 无活动页面时静默跳过
function releaseActivePageVoice() {
  if (typeof getCurrentPages !== 'function') {
    return;
  }
  try {
    const pages = getCurrentPages();
    const top = pages && pages.length > 0 ? pages[pages.length - 1] : null;
    if (top && typeof top.voiceExit === 'function') {
      top.voiceExit();
    }
  } catch (_e) {}
}

export default {
  onLaunch: function () {
  },
  onShow: function () {
  },
  onHide: function () {
    console.log('App Hide')
    releaseActivePageVoice()
  },
  onError: function (err) {
    console.log('App Error', err)
    releaseActivePageVoice()
  },
}
