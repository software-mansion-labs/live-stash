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

window.addEventListener('phx:live-stash:init-server', (event) => {
  node = event.detail.node;
  stashId = event.detail.stashId;
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
