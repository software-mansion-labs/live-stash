let stashedState = {};
let node = null;

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

window.addEventListener('phx:live-stash:save-node', (event) => {
  node = event.detail.node;
});

export default function initLiveStash(params) {
  return () => {
    return {
      stashedState: stashedState,
      node: node,
      ...params,
    };
  };
}
