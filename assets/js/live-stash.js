let stashedState = {}

window.addEventListener("phx:live-stash:reset", (_event) => {
  stashedState = {}
})

window.addEventListener("phx:live-stash:stash", (event) => {
  console.log("Stashing state:", event.detail.key, event.detail.value)
  stashedState[event.detail.key] = event.detail.value;
})

export default function initLiveStash(params) {
  return () => {
    return { "stashedState": stashedState, ...params }
  }
}
