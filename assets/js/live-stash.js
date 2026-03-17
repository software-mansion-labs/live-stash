let stashedState = {};
let node = null;
let stashId = null;

window.addEventListener('phx:live-stash:reset-state', (_event) => {
  stashedState = {};
});

window.addEventListener('phx:live-stash:stash-state', (event) => {
  stashedState[event.detail.key_hash] = {
    key: event.detail.key,
    value: event.detail.value,
  };
});

window.addEventListener('phx:live-stash:stash-id', (event) => {
  stashId = event.detail.stashId;
});

window.addEventListener('phx:live-stash:save-node', (event) => {
  node = event.detail.node;
});

export default function initLiveStash(params) {
  return () => {
    return {
      stashedState: stashedState,
      node: node,
      stashId: stashId,
      ...params,
    };
  };
}
