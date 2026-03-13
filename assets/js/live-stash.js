let stashedState = {};

window.addEventListener('phx:live-stash:reset-state', (_event) => {
  stashedState = {};
});

window.addEventListener('phx:live-stash:stash-state', (event) => {
  stashedState[event.detail.key_hash] = {
    key: event.detail.key,
    value: event.detail.value,
  };
});

export default function initLiveStash(params) {
  return () => {
    return { stashedState: stashedState, ...params };
  };
}
