let stashedState = {};
let node = null;

window.addEventListener('phx:live-stash:reset-state', (_event) => {
  stashedState = {};
});

window.addEventListener('phx:live-stash:stash-state', (event) => {
  stashedState[event.detail.key_hash] = {
    key: event.detail.key,
    value: event.detail.value,
  };
});

window.addEventListener('phx:live-stash:save-node', (event) => {
  node = event.detail.node;
});

window.addEventListener('phx:live-stash:reset-node', (_event) => {
  node = null;
});

export default function initLiveStash(params) {
  return () => {
    return { stashedState: stashedState, node: node, ...params };
  };
}
