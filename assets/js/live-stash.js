const liveStashStateKey = "live-stash-state"

const liveStashDefaultState = {
  status: "not-initialized",
  stashedState: {},
}

function getLiveStashState() {
  const state = sessionStorage.getItem(liveStashStateKey)
  return state ? JSON.parse(state) : liveStashDefaultState
}

window.addEventListener("phx:live-stash:init", (event) => {
  const currentState = getLiveStashState()
  const newState = { ...currentState, ...event.detail }

  sessionStorage.setItem(liveStashStateKey, JSON.stringify(newState))
})

window.addEventListener("phx:live-stash:stash", (event) => {
  const currentState = getLiveStashState()

  const stashedState = currentState.stashedState
  const key = event.detail.key
  const value = event.detail.value

  const newState = { ...currentState, stashedState: { ...stashedState, [key]: value } }
  sessionStorage.setItem(liveStashStateKey, JSON.stringify(newState))
})

export default function initLiveStash(params) {
  return () => {
    const currentState = getLiveStashState()
    return { "live-stash-state": currentState, ...params }
  }
}
