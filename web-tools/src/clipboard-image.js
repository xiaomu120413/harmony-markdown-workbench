// Only consume image bytes delivered by a real system paste event; never read the clipboard API.
export function handleImagePaste(event, snapshot, notify) {
  if (!event.isTrusted || !snapshot.editable) return;
  const items = Array.from(event.clipboardData?.items || []).filter(item => item.kind === 'file' && item.type.startsWith('image/'));
  if (!items.length) return;
  event.preventDefault();
  event.stopImmediatePropagation();
  const fail = error => notify('pasteImage', { s: snapshot.s, error });
  if (items.length !== 1) { fail('multiple'); return; }
  const file = items[0].getAsFile();
  if (!file) { fail('read'); return; }
  if (!/^image\/(png|jpeg|gif|webp|bmp)$/.test(file.type)) { fail('format'); return; }
  if (!file.size || file.size > 20 * 1024 * 1024) { fail('size'); return; }
  const reader = new FileReader();
  reader.onerror = () => fail('read');
  reader.onabort = () => fail('read');
  reader.onload = () => {
    if (typeof reader.result !== 'string') { fail('read'); return; }
    notify('pasteImage', { ...snapshot, data: reader.result });
  };
  try { reader.readAsDataURL(file); } catch (_) { fail('read'); }
}
