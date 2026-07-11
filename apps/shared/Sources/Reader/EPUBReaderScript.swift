import Foundation

enum EPUBReaderScript {
    static let source = #"""
    (() => {
      'use strict';
      const bridge = window.webkit?.messageHandlers?.citrationEPUB;
      if (!bridge || window.__citrationEPUBInstalled) return;
      window.__citrationEPUBInstalled = true;
      let base = '';
      let spineIndex = 0;
      let reportTimer;

      const send = (payload) => bridge.postMessage(payload);
      const textChildren = (node) => Array.from(node.childNodes).filter(child => child.nodeType === Node.TEXT_NODE);

      const stepForNode = (node) => {
        if (node.nodeType === Node.TEXT_NODE) {
          return 1 + 2 * textChildren(node.parentNode).indexOf(node);
        }
        return 2 * (Array.from(node.parentNode.children).indexOf(node) + 1);
      };

      const pathTo = (node, offset) => {
        const steps = [];
        let current = node;
        while (current?.parentNode && current.parentNode.nodeType !== Node.DOCUMENT_NODE) {
          steps.unshift(stepForNode(current));
          current = current.parentNode;
        }
        return '/' + steps.join('/') + (offset == null ? '' : ':' + offset);
      };

      const splitPath = (value) => {
        const clean = value.replace(/\[[^\]]*\]/g, '');
        const terminal = clean.match(/:(\d+)(?:\[[^\]]*\])?$/);
        const path = terminal ? clean.slice(0, terminal.index) : clean;
        const steps = Array.from(path.matchAll(/\/(\d+)/g), match => Number(match[1]));
        return { steps, offset: terminal ? Number(terminal[1]) : 0 };
      };

      const resolvePath = (value) => {
        const parsed = splitPath(value);
        let node = document.documentElement;
        for (const step of parsed.steps) {
          if (step % 2 === 0) {
            node = node?.children?.[(step / 2) - 1];
          } else {
            node = node ? textChildren(node)[(step - 1) / 2] : null;
          }
          if (!node) return null;
        }
        return { node, offset: Math.min(parsed.offset, node.length ?? node.childNodes.length) };
      };

      const cfiBody = (cfi) => {
        if (!cfi?.startsWith('epubcfi(') || !cfi.endsWith(')')) return null;
        return cfi.slice(8, -1).split('!')[1] ?? null;
      };

      const rangeFromCFI = (cfi) => {
        const body = cfiBody(cfi);
        if (!body) return null;
        const parts = body.split(',');
        let start;
        let end;
        if (parts.length === 3) {
          start = resolvePath(parts[0] + parts[1]);
          end = resolvePath(parts[0] + parts[2]);
        } else {
          start = resolvePath(parts[0]);
          end = start;
        }
        if (!start || !end) return null;
        const range = document.createRange();
        range.setStart(start.node, start.offset);
        range.setEnd(end.node, end.offset);
        return range;
      };

      const cfiFromRange = (range) => {
        const startPath = pathTo(range.startContainer, range.startOffset);
        if (range.collapsed) return `epubcfi(${base}!${startPath})`;
        const endPath = pathTo(range.endContainer, range.endOffset);
        const startSteps = startPath.split('/').slice(1);
        const endSteps = endPath.split('/').slice(1);
        const common = [];
        while (startSteps.length && endSteps.length && startSteps[0] === endSteps[0]) {
          common.push(startSteps.shift());
          endSteps.shift();
        }
        const commonPath = '/' + common.join('/');
        const startSuffix = '/' + startSteps.join('/');
        const endSuffix = '/' + endSteps.join('/');
        return `epubcfi(${base}!${commonPath},${startSuffix},${endSuffix})`;
      };

      const firstVisibleText = () => {
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        let node;
        while ((node = walker.nextNode())) {
          if (!node.nodeValue?.trim()) continue;
          const range = document.createRange();
          range.selectNodeContents(node);
          const rect = range.getBoundingClientRect();
          if (rect.bottom >= 0 && rect.top <= window.innerHeight) return node;
        }
        return null;
      };

      const reportProgress = () => {
        const node = firstVisibleText();
        if (!node) return;
        const range = document.createRange();
        range.setStart(node, 0);
        range.collapse(true);
        const extent = Math.max(document.documentElement.scrollHeight - window.innerHeight, 1);
        send({ type: 'progress', cfi: cfiFromRange(range), fraction: Math.max(0, Math.min(1, window.scrollY / extent)) });
      };

      const reportSelection = () => {
        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
          send({ type: 'selection', selection: null });
          return;
        }
        const range = selection.getRangeAt(0);
        const text = range.toString().replace(/\s+/g, ' ').trim();
        if (!text || !document.body.contains(range.commonAncestorContainer)) return;
        const prefix = document.createRange();
        prefix.setStart(document.body, 0);
        prefix.setEnd(range.startContainer, range.startOffset);
        const sortIndex = String(spineIndex).padStart(5, '0') + '|' + String(prefix.toString().length).padStart(8, '0');
        const position = {
          type: 'FragmentSelector',
          conformsTo: 'http://www.idpf.org/epub/linking/cfi/epub-cfi.html',
          value: cfiFromRange(range)
        };
        send({ type: 'selection', selection: { text, position: JSON.stringify(position), sortIndex } });
      };

      const themeColors = {
        light: ['#ffffff', '#1d1d1f'],
        sepia: ['#f4ecd8', '#3f3528'],
        dark: ['#1e1e1e', '#e8e8e8']
      };

      window.citrationEPUB = {
        configure(configuration) {
          base = configuration.base;
          spineIndex = configuration.spineIndex;
          const colors = themeColors[configuration.theme] ?? themeColors.light;
          document.documentElement.style.setProperty('background', colors[0], 'important');
          document.documentElement.style.setProperty('color', colors[1], 'important');
          document.body.style.setProperty('background', colors[0], 'important');
          document.body.style.setProperty('color', colors[1], 'important');
          document.body.style.setProperty('font-size', `${configuration.fontScale}em`, 'important');
          document.body.style.setProperty('line-height', '1.55', 'important');
          document.body.style.setProperty('max-width', '48em', 'important');
          document.body.style.setProperty('margin', '2.5em auto', 'important');
          document.body.style.setProperty('padding', '0 2em 5em', 'important');
        },
        restore(cfi) {
          const range = rangeFromCFI(cfi);
          range?.startContainer?.parentElement?.scrollIntoView({ block: 'start' });
        },
        navigateFragment(fragment) {
          document.getElementById(fragment)?.scrollIntoView({ block: 'start' });
        },
        find(query) {
          window.getSelection()?.removeAllRanges();
          window.find(query, false, false, true, false, true, false);
          window.getSelection()?.getRangeAt(0)?.startContainer?.parentElement?.scrollIntoView({ block: 'center' });
        },
        renderAnnotations(annotations) {
          if (!CSS.highlights || typeof Highlight === 'undefined') return;
          CSS.highlights.clear();
          const groups = new Map();
          for (const annotation of annotations) {
            const range = rangeFromCFI(annotation.cfi);
            if (!range) continue;
            const name = `citration-${annotation.kind}-${annotation.color.replace('#', '')}`;
            if (!groups.has(name)) groups.set(name, new Highlight());
            groups.get(name).add(range);
            if (!document.getElementById(name)) {
              const style = document.createElement('style');
              style.id = name;
              style.textContent = annotation.kind === 'underline'
                ? `::highlight(${name}) { text-decoration: underline 2px ${annotation.color}; }`
                : `::highlight(${name}) { background: ${annotation.color}88; }`;
              document.head.appendChild(style);
            }
          }
          for (const [name, group] of groups) CSS.highlights.set(name, group);
        },
        reportProgress
      };

      window.addEventListener('scroll', () => {
        clearTimeout(reportTimer);
        reportTimer = setTimeout(reportProgress, 180);
      }, { passive: true });
      document.addEventListener('selectionchange', () => setTimeout(reportSelection, 0));
      send({ type: 'ready' });
    })();
    """#
}
