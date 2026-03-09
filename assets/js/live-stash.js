let stashedState = {}

window.addEventListener("phx:live-stash:reset", (_event) => {
  stashedState = {}
})

window.addEventListener("phx:live-stash:stash", (event) => {
  stashedState[event.detail.key] = event.detail.value;
})

export default function initLiveStash(params) {
  return () => {
    return { "stashedState": stashedState, ...params }
  }
}
