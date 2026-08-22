(() => {
  'use strict';

  const status = document.querySelector('#status');
  const form = document.querySelector('#profile-form');
  const loginForm = document.querySelector('#login-form');
  const authState = document.querySelector('#auth-state');
  const authDownload = document.querySelector('#authenticated-download');
  const dialog = document.querySelector('#fixture-dialog');
  const source = document.querySelector('#drag-source');
  const target = document.querySelector('#drag-target');
  const upload = document.querySelector('#upload');
  const scrollRegion = document.querySelector('#scroll-region');
  const scrollItems = document.querySelector('#scroll-items');
  const staleTarget = document.querySelector('#stale-target');
  const takeoverState = document.querySelector('#takeover-state');
  let scrollCount = 0;
  let targetVersion = 1;

  const appendScrollBatch = () => {
    if (scrollCount >= 30) return;
    const fragment = document.createDocumentFragment();
    for (let index = 0; index < 10; index += 1) {
      const item = document.createElement('li');
      item.dataset.fixtureRow = String(scrollCount + index + 1);
      item.textContent = `scroll-item-${scrollCount + index + 1}`;
      fragment.appendChild(item);
    }
    scrollCount += 10;
    scrollItems.appendChild(fragment);
  };

  document.querySelector('#js-rendered').textContent = 'JavaScript rendered fixture';
  document.querySelector('#js-rendered').dataset.ready = 'true';

  loginForm.addEventListener('submit', (event) => {
    event.preventDefault();
    const data = new FormData(loginForm);
    const valid = data.get('user') === 'fixture-user' && data.get('passphrase') === 'fixture-pass';
    authState.textContent = valid ? 'signed-in' : 'denied';
    authDownload.hidden = !valid;
    status.textContent = valid ? 'auth:signed-in' : 'auth:denied';
  });

  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const data = new FormData(form);
    const confirmed = document.querySelector('#confirm').checked;
    status.textContent = `saved:${data.get('name') ?? ''}:${data.get('mode') ?? ''}:${confirmed}`;
  });

  document.querySelector('#open-dialog').addEventListener('click', () => {
    dialog.showModal();
  });
  document.querySelector('#close-dialog').addEventListener('click', () => {
    dialog.close();
  });

  source.addEventListener('dragstart', (event) => {
    event.dataTransfer.setData('text/plain', 'fixture-drag');
  });
  target.addEventListener('dragover', (event) => event.preventDefault());
  target.addEventListener('drop', (event) => {
    event.preventDefault();
    status.textContent = `drop:${event.dataTransfer.getData('text/plain')}`;
  });

  upload.addEventListener('change', () => {
    const file = upload.files?.[0];
    status.textContent = file ? `upload:${file.name}:${file.size}` : 'upload:none';
  });

  document.querySelector('#open-popup').addEventListener('click', () => {
    window.open('popup.html', 'p3-fixture-popup', 'width=420,height=320');
  });

  appendScrollBatch();
  scrollRegion.addEventListener('scroll', () => {
    const nearBottom = scrollRegion.scrollTop + scrollRegion.clientHeight >= scrollRegion.scrollHeight - 4;
    if (nearBottom) appendScrollBatch();
  });

  document.querySelector('#replace-target').addEventListener('click', () => {
    targetVersion += 1;
    const replacement = staleTarget.cloneNode(true);
    replacement.dataset.targetVersion = String(targetVersion);
    replacement.textContent = `Versioned target ${targetVersion}`;
    staleTarget.replaceWith(replacement);
    status.textContent = `target-replaced:${targetVersion}`;
  });

  document.querySelector('#request-takeover').addEventListener('click', () => {
    takeoverState.textContent = 'takeover-required';
    takeoverState.dataset.requiresFreshObservation = 'true';
    status.textContent = 'takeover:required';
  });

  console.info('p3-fixture-ready');
})();
