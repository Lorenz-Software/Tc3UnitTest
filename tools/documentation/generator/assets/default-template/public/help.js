(() => {
  'use strict';
  const root = document.documentElement;
  const themeButton = document.querySelector('.theme-toggle');
  let theme = 'light';
  try { theme = localStorage.getItem('library-help-theme') === 'dark' ? 'dark' : 'light'; } catch {}
  function applyTheme() {
    root.dataset.theme = theme;
    themeButton.title = 'Switch to ' + (theme === 'dark' ? 'light' : 'dark') + ' theme';
    themeButton.setAttribute('aria-label', 'Switch to ' + (theme === 'dark' ? 'light' : 'dark') + ' theme');
  }
  applyTheme();
  themeButton.addEventListener('click', () => {
    theme = theme === 'dark' ? 'light' : 'dark'; applyTheme();
    try { localStorage.setItem('library-help-theme', theme); } catch {}
  });
  const currentFile = decodeURIComponent(location.pathname.split('/').pop() || 'index.html');
  const index = Array.isArray(window.LIBRARY_HELP_SEARCH) ? window.LIBRARY_HELP_SEARCH : [];
  const current = index.find(item => item.url === currentFile);
  const owner = current?.kind === 'Guide' ? null : current?.owner ? index.find(item => item.url === current.owner) : current;
  const context = document.querySelector('#context-navigation');
  function contextLink(item) {
    const link = document.createElement('a'); link.href = item.url; link.textContent = item.name.split('.').pop();
    if (item.url === currentFile) link.setAttribute('aria-current', 'page');
    return link;
  }
  if (owner && context) {
    context.hidden = false;
    const label = document.createElement('h2'); label.className = 'nav-label'; label.textContent = 'Current element';
    context.append(label, contextLink(owner));
    const members = document.createElement('div'); members.className = 'nav-members';
    index.filter(item => item.owner === owner.url).forEach(item => members.append(contextLink(item)));
    context.append(members);
  }
  const guideNavigation = document.querySelector('.guide-navigation');
  const isGuide = currentFile === 'guide.html' || current?.kind === 'Guide';
  if (guideNavigation) guideNavigation.open = isGuide;
  document.querySelectorAll('#help-navigation > a, .guide-navigation a').forEach(link => {
    const target = new URL(link.getAttribute('href'), location.href);
    if (target.pathname === location.pathname && target.search === location.search) {
      link.setAttribute('aria-current', 'page');
    }
    else if ((isGuide && link.getAttribute('href') === 'guide.html')
      || (owner && link.getAttribute('href') === 'catalog.html')
      || (currentFile === 'catalog.html' && link.getAttribute('href') === 'catalog.html')) link.setAttribute('aria-current', 'location');
    else if (current && target.searchParams.get('group') === String(current.group)) link.setAttribute('aria-current', 'location');
  });
  const catalog = document.querySelector('.catalog-controls');
  if (catalog) {
    catalog.hidden = false;
    const query = document.querySelector('#catalog-query'), group = document.querySelector('#catalog-group');
    const category = document.querySelector('#catalog-category');
    const kind = document.querySelector('#catalog-kind'), rows = Array.from(document.querySelectorAll('tr[data-entry]'));
    const status = document.querySelector('#catalog-status'), previous = document.querySelector('#catalog-previous');
    const next = document.querySelector('#catalog-next'), pagination = document.querySelector('.catalog-pagination');
    const requestedGroup = new URLSearchParams(location.search).get('group');
    if (Array.from(group.options).some(option => option.value === requestedGroup)) group.value = requestedGroup;
    const requestedCategory = new URLSearchParams(location.search).get('category');
    if (Array.from(category.options).some(option => option.value === requestedCategory)) category.value = requestedCategory;
    const pageSize = 50; let page = 0;
    const entries = rows.map(row => ({ row, text: row.textContent.toLowerCase() }));
    function refresh() {
      const terms = query.value.trim().toLowerCase().split(/\s+/).filter(Boolean);
      const matches = entries.filter(entry => (!group.value || entry.row.dataset.group === group.value)
        && (!category.value || entry.row.dataset.category === category.value) && (!kind.value || entry.row.dataset.kind === kind.value) && terms.every(term => entry.text.includes(term)));
      const pages = Math.max(1, Math.ceil(matches.length / pageSize)); page = Math.min(page, pages - 1);
      rows.forEach(row => { row.hidden = true; });
      matches.slice(page * pageSize, (page + 1) * pageSize).forEach(entry => { entry.row.hidden = false; });
      status.textContent = matches.length + ' of ' + rows.length + ' elements';
      document.querySelector('#catalog-page').textContent = 'Page ' + (page + 1) + ' of ' + pages;
      pagination.hidden = matches.length <= pageSize; previous.disabled = page === 0; next.disabled = page === pages - 1;
    }
    [query, group, category, kind].forEach(control => control.addEventListener(control === query ? 'input' : 'change', () => { page = 0; refresh(); }));
    previous.addEventListener('click', () => { page--; refresh(); });
    next.addEventListener('click', () => { page++; refresh(); });
    refresh();
  }
  const outline = document.querySelector('#page-outline');
  document.querySelectorAll('.guide-content table').forEach(table => {
    const wrapper = document.createElement('div'); wrapper.className = 'table-scroll';
    table.before(wrapper); wrapper.append(table); table.classList.add('api-table');
  });
  const ids = new Set();
  document.querySelectorAll('article h2,article h3').forEach(heading => {
    const base = heading.textContent.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'section';
    let id = heading.id || base, suffix = 2;
    while (ids.has(id)) id = base + '-' + suffix++;
    ids.add(id); heading.id = id;
    const link = document.createElement('a'); link.href = '#' + id; link.textContent = heading.textContent; outline.append(link);
  });
  const input = document.querySelector('#help-search');
  const searchDialog = document.querySelector('#help-search-dialog');
  function openSearch() { searchDialog.showModal(); input.focus(); }
  document.querySelector('.header-search').addEventListener('click', openSearch);
  document.querySelector('.search-close').addEventListener('click', () => searchDialog.close());
  searchDialog.addEventListener('click', event => {
    const bounds = searchDialog.getBoundingClientRect();
    if (event.target === searchDialog && (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom)) searchDialog.close();
  });
  const panel = document.querySelector('#help-results');
  const status = document.querySelector('#help-search-status');
  const results = panel.querySelector('ul');
  function search() {
    const query = input.value.trim().toLowerCase();
    panel.hidden = !query; results.replaceChildren();
    document.querySelector('.search-hint').hidden = Boolean(query);
    if (!query) return;
    const terms = query.split(/\s+/);
    const matches = index.filter(item => terms.every(term => (item.name + ' ' + item.text).toLowerCase().includes(term)))
      .sort((a, b) => Number(b.name.toLowerCase().includes(query)) - Number(a.name.toLowerCase().includes(query)) || a.name.localeCompare(b.name));
    status.textContent = matches.length + (matches.length === 1 ? ' result' : ' results') + (matches.length > 30 ? ' · showing first 30' : '');
    matches.slice(0, 30).forEach(item => {
      const row = document.createElement('li'), link = document.createElement('a'), name = document.createElement('strong'), snippet = document.createElement('span');
      link.href = item.url; name.textContent = item.name;
      const content = item.text.replace(/\s+/g, ' '), hit = content.toLowerCase().indexOf(terms[0]), start = Math.max(0, hit - 30);
      snippet.textContent = item.kind + ' · ' + (start ? '…' : '') + content.slice(start, start + 150) + (content.length > start + 150 ? '…' : '');
      link.append(name, snippet); row.append(link); results.append(row);
    });
  }
  input.addEventListener('input', search);
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && searchDialog.open) {
      event.preventDefault(); searchDialog.close(); return;
    }
    if ((event.key.toLowerCase() === 'k' && (event.ctrlKey || event.metaKey))
      || (event.key === '/' && !event.ctrlKey && !event.metaKey && !event.altKey && !/input|textarea|select/i.test(event.target.tagName) && !event.target.isContentEditable)) {
      event.preventDefault();
      if (searchDialog.open) { if (event.key !== '/') searchDialog.close(); }
      else openSearch();
    }
  });
  document.querySelector('.menu-toggle').addEventListener('click', event => {
    const open = document.body.classList.toggle('menu-open'); event.currentTarget.setAttribute('aria-expanded', String(open));
  });
})();
