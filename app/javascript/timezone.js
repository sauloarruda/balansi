// Detect browser timezone and store in cookie
(function() {
  try {
    const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    // Store timezone in a cookie that can be read by Rails
    document.cookie = `timezone=${encodeURIComponent(timezone)}; path=/; max-age=${60 * 60 * 24 * 365}`; // 1 year
  } catch (e) {
    console.warn('Could not detect timezone:', e);
    // Cookie will default to 'America/Sao_Paulo' in ApplicationController
  }
})();