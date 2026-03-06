let stashedState = {}

window.addEventListener("phx:live-stash:reset", (_event) => {
  stashedState = {}
})

window.addEventListener("phx:page-loading-start", (info) => {


  if (info.detail && info.detail.kind === "redirect" || info.detail.kind === "patch") {
    stashedState = {};
  }
});

window.addEventListener("phx:live-stash:stash", (event) => {
  stashedState[event.detail.key] = event.detail.value;
})

export default function initLiveStash(params) {
  return () => {
    return { "stashedState": stashedState, ...params }
  }
}
