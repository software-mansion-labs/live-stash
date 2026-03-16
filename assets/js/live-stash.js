let stashedState = {};
let stashedKeys = null;
let node = null;

window.addEventListener('phx:live-stash:reset-state', (_event) => {
  stashedState = {};
  stashedKeys = {};
});

window.addEventListener('phx:live-stash:stash-state', (event) => {
  stashedState[event.detail.key] = event.detail.value;
});

window.addEventListener('phx:live-stash:stash-keys', (event) => {
  stashedKeys = event.detail.keys;
});

window.addEventListener('phx:live-stash:save-node', (event) => {
  node = event.detail.node;
});

export default function initLiveStash(params) {
  return () => {
    return {
      stashedState: stashedState,
      stashedKeys: stashedKeys,
      node: node,
      ...params,
    };
  };
}
