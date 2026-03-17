let stashedState = {};
let node = null;
let stashId = null;

window.addEventListener('phx:live-stash:reset-state', (_event) => {
  stashedState = {};
});

window.addEventListener('phx:live-stash:stash-state', (event) => {
  stashedState['assigns'] = stashedState['assigns'] || {};

  stashedState['assigns'] = {
    ...stashedState['assigns'],
    ...event.detail.assigns,
  };

  stashedState['keys'] = event.detail.keys;
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
