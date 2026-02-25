// File attachment handling
export function setupAttachments(attachBtn, fileInput, onAttachment) {
  attachBtn.addEventListener('click', () => fileInput.click());

  fileInput.addEventListener('change', async () => {
    const files = fileInput.files;
    if (!files.length) return;

    for (const file of files) {
      try {
        const base64 = await fileToBase64(file);
        onAttachment(file.name, base64);
      } catch (e) {
        console.error('Failed to read file:', e);
      }
    }
    fileInput.value = '';
  });
}

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      // result is "data:mime;base64,XXXX" — extract just the base64 part
      const result = reader.result;
      const idx = result.indexOf(',');
      resolve(idx >= 0 ? result.substring(idx + 1) : result);
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}
