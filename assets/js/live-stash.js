let liveStash = {};

window.addEventListener('phx:live-stash:init-browser-memory', (_event) => {
  liveStash = { stashedState: null };
});

window.addEventListener('phx:live-stash:stash-state', (event) => {
  liveStash['stashedState'] = event.detail.assigns;
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
