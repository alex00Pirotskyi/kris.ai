(() => {
  'use strict';
  const status = document.querySelector('#status');
  const form = document.querySelector('#profile-form');
  const dialog = document.querySelector('#fixture-dialog');
  const source = document.querySelector('#drag-source');
  const target = document.querySelector('#drag-target');
  const upload = document.querySelector('#upload');

  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const data = new FormData(form);
    status.textContent = `saved:${data.get('name') ?? ''}:${data.get('mode') ?? ''}`;
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
  console.info('p3-fixture-ready');
})();
