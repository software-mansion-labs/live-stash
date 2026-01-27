const liveStashDefaultState = {
  status: "not-initialized",
  stashedState: {},
}

let state = liveStashDefaultState

window.addEventListener("phx:live-stash:init", (event) => {
  state = { ...state, ...event.detail };
})

window.addEventListener("phx:live-stash:stash", (event) => {
  state.stashedState[event.detail.key] = event.detail.value;
})

export default function initLiveStash(params) {
  return () => {
    return { "live-stash-state": state, ...params }
  }
}
