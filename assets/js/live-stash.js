let liveStash = {};

window.addEventListener('phx:live-stash:init-browser-memory', (_event) => {
  liveStash = { stashedState: {} };
});

window.addEventListener('phx:live-stash:stash-state', (event) => {
  if (!liveStash.stashedState) {
    liveStash.stashedState = {};
  }

  liveStash.stashedState['assigns'] = liveStash.stashedState['assigns'] || {};

  liveStash.stashedState['assigns'] = {
    ...liveStash.stashedState['assigns'],
    ...event.detail.assigns,
  };

  liveStash.stashedState['keys'] = event.detail.keys;
});

window.addEventListener('phx:live-stash:init-ets', (event) => {
  liveStash = {
    node: event.detail.node,
    stashId: event.detail.stashId,
  };
});

export default function initLiveStash(params) {
  return () => {
    return {
      liveStash: liveStash,
      ...params,
    };
  };
}
