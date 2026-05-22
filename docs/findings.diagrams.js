(function () {
  'use strict';

  const COLORS = {
    ink: '#1f1f1f',
    muted: '#999',
    soft: '#bbb',
    sage: '#5b7a5a',
    terracotta: '#a85a3a',
    cream: '#fbf9f4',
    paper: '#f6f1e6'
  };

  const FONT_SANS = "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, Arial, sans-serif";
  const FONT_MONO = "'SF Mono', 'Menlo', 'Monaco', 'Consolas', monospace";

  // ---------- helpers ----------

  function getContainer(sel) {
    const node = document.querySelector(sel);
    if (!node) {
      console.warn('findings.diagrams: missing container', sel);
      return null;
    }
    return node;
  }

  function makeSvg(container, width, height) {
    return d3.select(container)
      .append('svg')
      .attr('width', width)
      .attr('height', height)
      .attr('viewBox', `0 0 ${width} ${height}`)
      .attr('xmlns', 'http://www.w3.org/2000/svg')
      .attr('font-family', FONT_SANS)
      .style('max-width', '100%')
      .style('height', 'auto')
      .style('display', 'block');
  }

  function arrowMarker(svg, id, color) {
    svg.append('defs').append('marker')
      .attr('id', id)
      .attr('viewBox', '0 -5 10 10')
      .attr('refX', 9)
      .attr('refY', 0)
      .attr('markerWidth', 7)
      .attr('markerHeight', 7)
      .attr('orient', 'auto')
      .append('path')
      .attr('d', 'M0,-4L9,0L0,4')
      .attr('fill', color);
  }

  function drawBox(svg, x, y, w, h, opts) {
    opts = opts || {};
    return svg.append('rect')
      .attr('x', x)
      .attr('y', y)
      .attr('width', w)
      .attr('height', h)
      .attr('rx', opts.rx || 2)
      .attr('ry', opts.ry || 2)
      .attr('fill', opts.fill || 'none')
      .attr('stroke', opts.stroke || COLORS.ink)
      .attr('stroke-width', opts.strokeWidth || 1)
      .attr('stroke-dasharray', opts.dash || null);
  }

  function drawLabel(svg, x, y, text, opts) {
    opts = opts || {};
    return svg.append('text')
      .attr('x', x)
      .attr('y', y)
      .attr('font-size', opts.size || 12)
      .attr('font-family', opts.mono ? FONT_MONO : FONT_SANS)
      .attr('font-weight', opts.weight || 'normal')
      .attr('fill', opts.fill || COLORS.ink)
      .attr('text-anchor', opts.anchor || 'start')
      .attr('dominant-baseline', opts.baseline || 'alphabetic')
      .text(text);
  }

  function drawArrow(svg, x1, y1, x2, y2, opts) {
    opts = opts || {};
    return svg.append('line')
      .attr('x1', x1)
      .attr('y1', y1)
      .attr('x2', x2)
      .attr('y2', y2)
      .attr('stroke', opts.stroke || COLORS.ink)
      .attr('stroke-width', opts.strokeWidth || 1)
      .attr('stroke-dasharray', opts.dash || null)
      .attr('marker-end', opts.marker ? `url(#${opts.marker})` : null);
  }

  // ---------- Diagram 1: Architecture ----------

  function renderArchitecture(sel) {
    const container = getContainer(sel);
    if (!container) return;

    const W = 780;
    const H = 760;
    const svg = makeSvg(container, W, H);
    arrowMarker(svg, 'arch-arrow', COLORS.ink);
    arrowMarker(svg, 'arch-arrow-muted', COLORS.muted);

    // Top: Claude Code session
    const ccW = 220;
    const ccX = (W - ccW) / 2;
    drawBox(svg, ccX, 16, ccW, 38, { fill: COLORS.paper });
    drawLabel(svg, W / 2, 40, 'Claude Code session', {
      anchor: 'middle', size: 13, weight: 600
    });

    // Arrow into FastAPI box
    drawArrow(svg, W / 2, 54, W / 2, 84, { marker: 'arch-arrow' });

    // Middle: FastAPI container
    const fapiX = 30;
    const fapiY = 90;
    const fapiW = W - 60;
    const fapiH = 380;
    drawBox(svg, fapiX, fapiY, fapiW, fapiH, { fill: COLORS.paper });
    drawLabel(svg, fapiX + 14, fapiY + 22, 'FastAPI app', {
      size: 13, weight: 700
    });
    drawLabel(svg, fapiX + 14, fapiY + 40,
      'uvicorn 127.0.0.1:8000  ·  OriginValidation MW', {
        size: 11, mono: true, fill: COLORS.muted
      });

    // Mounted sub-apps area (left side)
    const subX = fapiX + 18;
    const subTop = fapiY + 60;
    const subW = 380;

    // /cortex/mcp
    let curY = subTop;
    drawBox(svg, subX, curY, subW, 110, { stroke: COLORS.sage, fill: COLORS.cream });
    drawLabel(svg, subX + 10, curY + 18, '/cortex/mcp', {
      size: 12, mono: true, weight: 700, fill: COLORS.sage
    });
    drawLabel(svg, subX + 10, curY + 34,
      'FastMCP "cortex" sub-app  ·  v from importlib.metadata', {
        size: 10, fill: COLORS.muted
      });
    const cortexTools = [
      'store_memory', 'search_memories', 'recent_memories',
      'get_memory', 'add_to_diary', 'read_from_diary'
    ];
    cortexTools.forEach((t, i) => {
      const col = i % 3;
      const row = Math.floor(i / 3);
      drawLabel(svg, subX + 14 + col * 124, curY + 56 + row * 18, t, {
        size: 11, mono: true
      });
    });

    // /utils/mcp
    curY += 124;
    drawBox(svg, subX, curY, subW, 56, { stroke: COLORS.sage, fill: COLORS.cream });
    drawLabel(svg, subX + 10, curY + 18, '/utils/mcp', {
      size: 12, mono: true, weight: 700, fill: COLORS.sage
    });
    drawLabel(svg, subX + 10, curY + 34,
      'FastMCP "utils" sub-app', {
        size: 10, fill: COLORS.muted
      });
    drawLabel(svg, subX + 14, curY + 50,
      'fetch  (URL -> Markdown · three-tier · SSRF-defended)', {
        size: 11, mono: true
      });

    // /hooks
    curY += 70;
    drawBox(svg, subX, curY, subW, 78, { stroke: COLORS.sage, fill: COLORS.cream });
    drawLabel(svg, subX + 10, curY + 18, '/hooks/*', {
      size: 12, mono: true, weight: 700, fill: COLORS.sage
    });
    drawLabel(svg, subX + 10, curY + 34,
      'APIRouter (UserPromptSubmit + Stop)', {
        size: 10, fill: COLORS.muted
      });
    ['/hooks/timestamp', '/hooks/memories', '/hooks/reflection'].forEach((t, i) => {
      drawLabel(svg, subX + 14, curY + 52 + i * 14, t, {
        size: 10, mono: true
      });
    });

    // /livez
    curY += 92;
    drawBox(svg, subX, curY, subW, 30, { stroke: COLORS.sage, fill: COLORS.cream });
    drawLabel(svg, subX + 10, curY + 19,
      '/livez   ·   unauthenticated health check', {
        size: 11, mono: true
      });

    // Long-lived singletons panel (right side inside FastAPI)
    const sgX = fapiX + 420;
    const sgY = fapiY + 60;
    const sgW = fapiW - 420 - 18;
    const sgH = 320;
    drawBox(svg, sgX, sgY, sgW, sgH, { stroke: COLORS.soft, dash: '3,3' });
    drawLabel(svg, sgX + 10, sgY + 18, 'long-lived singletons', {
      size: 11, weight: 700, fill: COLORS.muted
    });
    const singletons = [
      ['asyncpg.Pool', 'db.get_pool()'],
      ['AsyncOpenAI chat', 'llm.get_chat_client()'],
      ['AsyncOpenAI embed', 'llm.get_embedding_client()'],
      ['redis.asyncio.Redis', 'app.state.redis (lifespan)']
    ];
    singletons.forEach((s, i) => {
      const ry = sgY + 36 + i * 64;
      drawBox(svg, sgX + 10, ry, sgW - 20, 50, {
        stroke: COLORS.ink, fill: COLORS.paper
      });
      drawLabel(svg, sgX + 18, ry + 20, s[0], {
        size: 12, weight: 700
      });
      drawLabel(svg, sgX + 18, ry + 38, s[1], {
        size: 10, mono: true, fill: COLORS.muted
      });
    });

    // Bottom: three target boxes
    const tgtY = fapiY + fapiH + 50;
    const tgtH = 120;
    const tgtW = 220;
    const tgtGap = (W - 60 - tgtW * 3) / 2;
    const tgts = [
      {
        title: 'Postgres + pgvector',
        lines: [
          'cortex.memories',
          'cortex.diary',
          'search_path: public, extensions'
        ]
      },
      {
        title: 'Redis',
        lines: [
          'seen:<sid>',
          'last-msg:<sid>',
          'reflection:turn:<sid>'
        ]
      },
      {
        title: 'Bifrost LLM gateway',
        lines: [
          'chat (OpenAI-protocol)',
          'embedding (Qwen 3 4B)',
          ''
        ]
      }
    ];
    const tgtXs = [];
    tgts.forEach((t, i) => {
      const x = 30 + i * (tgtW + tgtGap);
      tgtXs.push(x);
      drawBox(svg, x, tgtY, tgtW, tgtH, { fill: COLORS.paper });
      drawLabel(svg, x + 12, tgtY + 22, t.title, { size: 13, weight: 700 });
      t.lines.forEach((ln, j) => {
        drawLabel(svg, x + 12, tgtY + 44 + j * 18, ln, {
          size: 11, mono: true, fill: ln ? COLORS.ink : COLORS.muted
        });
      });
    });

    // Arrows from FastAPI to each target with labels
    const fapiBottomY = fapiY + fapiH;
    const fapiCenterX = fapiX + fapiW / 2;
    const labels = [
      'asyncpg.Pool',
      'redis.asyncio',
      'AsyncOpenAI (chat + embed)'
    ];
    tgtXs.forEach((tx, i) => {
      const cx = tx + tgtW / 2;
      // bend through a kink point
      const midY = fapiBottomY + 26;
      svg.append('path')
        .attr('d',
          `M ${fapiCenterX} ${fapiBottomY} ` +
          `L ${fapiCenterX} ${midY} ` +
          `L ${cx} ${midY} ` +
          `L ${cx} ${tgtY - 1}`)
        .attr('fill', 'none')
        .attr('stroke', COLORS.ink)
        .attr('stroke-width', 1)
        .attr('marker-end', 'url(#arch-arrow)');
      drawLabel(svg, cx, midY - 6, labels[i], {
        size: 10, mono: true, anchor: 'middle', fill: COLORS.muted
      });
    });

    // Caption
    drawLabel(svg, W / 2, H - 8,
      'one process, two MCP surfaces, three hooks, four singletons', {
        size: 11, anchor: 'middle', fill: COLORS.muted
      });
  }

  // ---------- Diagram 2: Hook flow ----------

  function renderHookFlow(sel) {
    const container = getContainer(sel);
    if (!container) return;

    const W = 780;
    const H = 460;
    const svg = makeSvg(container, W, H);
    arrowMarker(svg, 'hook-arrow-sage', COLORS.sage);
    arrowMarker(svg, 'hook-arrow-terra', COLORS.terracotta);
    arrowMarker(svg, 'hook-arrow-ink', COLORS.ink);

    // Top: emitter
    const emW = 280;
    const emX = (W - emW) / 2;
    drawBox(svg, emX, 16, emW, 38, { fill: COLORS.paper });
    drawLabel(svg, W / 2, 40, 'Claude Code session', {
      anchor: 'middle', size: 13, weight: 600
    });
    drawLabel(svg, W / 2, 64, 'emits hook events on each turn', {
      anchor: 'middle', size: 10, fill: COLORS.muted
    });

    // Two lane headers
    const laneTop = 90;
    const laneW = (W - 60 - 20) / 2;
    const leftLaneX = 30;
    const rightLaneX = leftLaneX + laneW + 20;

    drawBox(svg, leftLaneX, laneTop, laneW, H - laneTop - 60, {
      stroke: COLORS.sage, dash: '4,3'
    });
    drawBox(svg, rightLaneX, laneTop, laneW, H - laneTop - 60, {
      stroke: COLORS.terracotta, dash: '4,3'
    });
    drawLabel(svg, leftLaneX + 12, laneTop + 20, 'ALPHA HOOKS', {
      size: 11, weight: 700, fill: COLORS.sage
    });
    drawLabel(svg, rightLaneX + 12, laneTop + 20, 'DECIDUOUS HOOKS', {
      size: 11, weight: 700, fill: COLORS.terracotta
    });
    drawLabel(svg, leftLaneX + 12, laneTop + 36, 'in-process FastAPI endpoints', {
      size: 10, fill: COLORS.muted
    });
    drawLabel(svg, rightLaneX + 12, laneTop + 36, 'shell scripts under .claude/hooks/', {
      size: 10, fill: COLORS.muted
    });

    const rowsLeft = [
      {
        ev: 'UserPromptSubmit',
        ep: '/hooks/timestamp',
        note: 'PSO-8601 time + gap-since-last-message'
      },
      {
        ev: 'UserPromptSubmit',
        ep: '/hooks/memories',
        note: 'recall pipeline; returns ## Memory #N blocks'
      },
      {
        ev: 'Stop',
        ep: '/hooks/reflection',
        note: 'every 3rd turn · {decision:"block", reason: …}'
      }
    ];
    const rowsRight = [
      {
        ev: 'PreToolUse(Edit|Write)',
        ep: 'require-action-node.sh',
        note: 'block if no recent action/goal node'
      },
      {
        ev: 'PreToolUse(Bash)',
        ep: 'version-check.sh',
        note: 'guard the deciduous binary'
      },
      {
        ev: 'PostToolUse(Bash)',
        ep: 'post-commit-reminder.sh',
        note: 'advisory only'
      }
    ];

    function drawRow(x, y, w, ev, ep, note, color, marker) {
      drawBox(svg, x, y, w, 72, { fill: COLORS.cream });
      drawLabel(svg, x + 12, y + 18, ev, {
        size: 11, mono: true, weight: 700
      });
      drawLabel(svg, x + 12, y + 35, '->', { size: 11, mono: true, fill: color });
      drawLabel(svg, x + 30, y + 35, ep, {
        size: 11, mono: true, fill: color, weight: 600
      });
      drawLabel(svg, x + 12, y + 56, note, {
        size: 10, fill: COLORS.muted
      });
      // emitter arrow
      drawArrow(svg, x + w / 2, laneTop + 50, x + w / 2, y - 1, {
        stroke: color, marker: marker
      });
    }

    const rowGap = 14;
    const rowStartY = laneTop + 60;
    rowsLeft.forEach((r, i) => {
      drawRow(
        leftLaneX + 14,
        rowStartY + i * (72 + rowGap),
        laneW - 28,
        r.ev, r.ep, r.note,
        COLORS.sage,
        'hook-arrow-sage'
      );
    });
    rowsRight.forEach((r, i) => {
      drawRow(
        rightLaneX + 14,
        rowStartY + i * (72 + rowGap),
        laneW - 28,
        r.ev, r.ep, r.note,
        COLORS.terracotta,
        'hook-arrow-terra'
      );
    });

    // Bottom caption
    drawLabel(svg, W / 2, H - 26,
      'Two pipelines share one settings.json.', {
        size: 11, anchor: 'middle', fill: COLORS.ink, weight: 600
      });
    drawLabel(svg, W / 2, H - 10,
      'They never collide because they fire on different events.', {
        size: 11, anchor: 'middle', fill: COLORS.muted
      });
  }

  // ---------- Diagram 3: Recall pipeline ----------

  function renderRecallPipeline(sel) {
    const container = getContainer(sel);
    if (!container) return;

    const W = 820;
    const H = 280;
    const svg = makeSvg(container, W, H);
    arrowMarker(svg, 'recall-arrow', COLORS.ink);

    const steps = [
      {
        title: 'Extract queries',
        sub: 'Qwen chat, JSON-array',
        long: 'decompose prompt into semantic-search queries'
      },
      {
        title: 'Batch-embed',
        sub: 'Qwen 3 Embedding 4B',
        long: 'one HTTP request, one forward pass'
      },
      {
        title: 'Fetch seen:<sid>',
        sub: 'Redis SMEMBERS',
        long: 'per-session dedupe set'
      },
      {
        title: 'pgvector cosine',
        sub: 'top-1 per query',
        long: 'score >= 0.1'
      },
      {
        title: 'Merge + dedupe',
        sub: 'by memory id',
        long: 'keep best score'
      },
      {
        title: 'SADD to seen',
        sub: 'Redis · 7d TTL',
        long: 'mark these as seen'
      },
      {
        title: 'Format blocks',
        sub: '## Memory #N',
        long: 'return as additionalContext'
      }
    ];

    const stepW = 100;
    const stepH = 86;
    const gap = ((W - 40) - steps.length * stepW) / (steps.length - 1);
    const stepY = 50;

    const centers = [];

    steps.forEach((s, i) => {
      const x = 20 + i * (stepW + gap);
      centers.push(x + stepW / 2);
      drawBox(svg, x, stepY, stepW, stepH, { fill: COLORS.paper });
      // step number
      drawLabel(svg, x + stepW / 2, stepY - 10, String(i + 1), {
        size: 11, anchor: 'middle', fill: COLORS.muted, weight: 700, mono: true
      });
      drawLabel(svg, x + stepW / 2, stepY + 22, s.title, {
        size: 12, anchor: 'middle', weight: 700
      });
      drawLabel(svg, x + stepW / 2, stepY + 40, s.sub, {
        size: 10, anchor: 'middle', mono: true, fill: COLORS.ink
      });
      // wrap "long" — short enough as-is
      drawLabel(svg, x + stepW / 2, stepY + 60, s.long, {
        size: 9, anchor: 'middle', fill: COLORS.muted
      });
    });

    // arrows between steps
    for (let i = 0; i < steps.length - 1; i++) {
      const x1 = 20 + i * (stepW + gap) + stepW;
      const x2 = 20 + (i + 1) * (stepW + gap);
      drawArrow(svg, x1 + 2, stepY + stepH / 2, x2 - 2, stepY + stepH / 2, {
        marker: 'recall-arrow'
      });
    }

    // "lives where" annotation
    const annY = stepY + stepH + 32;
    drawLabel(svg, 20, annY, 'lives in', {
      size: 10, weight: 700, fill: COLORS.muted
    });

    const lives = [
      'chat client',
      'embedding client',
      'Redis',
      'asyncpg pool',
      'in-process',
      'Redis',
      'in-process'
    ];
    lives.forEach((l, i) => {
      drawLabel(svg, centers[i], annY + 20, l, {
        size: 10, anchor: 'middle', mono: true, fill: COLORS.muted
      });
      // thin tick connecting step to label
      svg.append('line')
        .attr('x1', centers[i])
        .attr('y1', stepY + stepH + 4)
        .attr('x2', centers[i])
        .attr('y2', annY + 6)
        .attr('stroke', COLORS.soft)
        .attr('stroke-width', 0.75)
        .attr('stroke-dasharray', '2,2');
    });

    drawLabel(svg, W / 2, H - 12,
      'tensor cores get to do their job in one forward pass instead of N', {
        size: 11, anchor: 'middle', fill: COLORS.muted
      });
  }

  // ---------- Diagram 4: Ecosystem ----------

  function renderEcosystem(sel) {
    const container = getContainer(sel);
    if (!container) return;

    const W = 820;
    const H = 600;
    const svg = makeSvg(container, W, H);

    // Tier styling
    function tierStyle(tier) {
      switch (tier) {
        case 'substrate':
          return { stroke: COLORS.ink, strokeWidth: 1.5, fill: COLORS.paper };
        case 'integrated':
          return { stroke: COLORS.sage, strokeWidth: 1.25, fill: COLORS.cream };
        case 'reference':
          return { stroke: COLORS.ink, strokeWidth: 1, fill: COLORS.cream };
        case 'mentioned':
          return { stroke: COLORS.soft, strokeWidth: 1, fill: COLORS.cream };
        case 'deciduous':
          return { stroke: COLORS.terracotta, strokeWidth: 1.25, fill: COLORS.cream };
        default:
          return { stroke: COLORS.ink, strokeWidth: 1, fill: COLORS.cream };
      }
    }

    const nodes = [
      { id: 'Alpha',                 tier: 'substrate',  role: 'substrate',           x: 410, y: 300 },
      { id: 'Alpha-dotclaude',       tier: 'integrated', role: '.claude config',      x: 250, y: 200 },
      { id: 'Alpha-System-Prompts',  tier: 'integrated', role: 'legacy persona',      x: 540, y: 175 },
      { id: 'agent-fleet',           tier: 'integrated', role: 'plugin marketplace',  x: 110, y: 240 },
      { id: 'Loom-dotclaude',        tier: 'integrated', role: 'alt .claude pattern', x: 270, y: 90  },
      { id: 'Claude-Hooks',          tier: 'reference',  role: 'alt hooks pipeline',  x: 130, y: 120 },
      { id: 'Intro',                 tier: 'reference',  role: 'metacognitive layer', x: 240, y: 410 },
      { id: 'Alpha-SDK',             tier: 'reference',  role: 'Python over stdio',   x: 410, y: 460 },
      { id: 'House-SDK',             tier: 'reference',  role: 'sibling AI',          x: 250, y: 530 },
      { id: 'Rosemary-SDK',          tier: 'reference',  role: "Kylee's AI",          x: 580, y: 530 },
      { id: 'pondside-sdk',          tier: 'reference',  role: 'shared utilities',    x: 690, y: 410 },
      { id: 'Loom',                  tier: 'mentioned',  role: 'HTTP proxy',          x: 430, y: 70  },
      { id: 'Deliverator',           tier: 'mentioned',  role: 'routing layer',       x: 570, y: 90  },
      { id: 'Argonath',              tier: 'mentioned',  role: 'observation proxy',   x: 700, y: 120 },
      { id: 'Forge',                 tier: 'mentioned',  role: 'GPU arbiter',         x: 770, y: 240 },
      { id: 'Routines',              tier: 'mentioned',  role: 'autonomous exec',     x: 720, y: 320 },
      { id: 'Duckpond',              tier: 'mentioned',  role: 'chat UI',             x: 580, y: 400 },
      { id: 'Cortex',                tier: 'mentioned',  role: 'sibling lib',         x: 120, y: 360 },
      { id: 'Pulse',                 tier: 'mentioned',  role: 'scheduled jobs',      x: 100, y: 450 },
      { id: 'deciduous',             tier: 'deciduous',  role: 'NOT a Pondsider',     x: 600, y: 250 }
    ];

    const edges = [
      ['Alpha-dotclaude',      'Alpha',            'configures'],
      ['Alpha-System-Prompts', 'Alpha',            'older persona'],
      ['agent-fleet',          'Alpha-dotclaude',  'plugin to'],
      ['Loom-dotclaude',       'Loom',             'paired'],
      ['Claude-Hooks',         'Intro',            'calls'],
      ['Claude-Hooks',         'Loom',             'via Deliverator'],
      ['Loom',                 'Deliverator',      'routes via'],
      ['Deliverator',          'Argonath',         'observed by'],
      ['Argonath',             'Loom',             'observes'],
      ['Alpha-dotclaude',      'Alpha-SDK',        'uses'],
      ['House-SDK',            'Alpha-SDK',        'sibling'],
      ['Rosemary-SDK',         'Alpha-SDK',        'sibling'],
      ['Duckpond',             'Alpha-SDK',        'driver'],
      ['Routines',             'Alpha-SDK',        'driver'],
      ['Forge',                'Alpha',            'substrate utility'],
      ['deciduous',            'Alpha',            'integrated alongside']
    ];

    const nodeById = {};
    nodes.forEach(n => { nodeById[n.id] = n; });

    // edges first
    edges.forEach(e => {
      const a = nodeById[e[0]];
      const b = nodeById[e[1]];
      if (!a || !b) return;
      svg.append('line')
        .attr('x1', a.x).attr('y1', a.y)
        .attr('x2', b.x).attr('y2', b.y)
        .attr('stroke', COLORS.soft)
        .attr('stroke-width', 0.9)
        .append('title').text(e[2]);
    });

    // nodes
    const nodeW = 124;
    const nodeH = 30;
    nodes.forEach(n => {
      const st = tierStyle(n.tier);
      const x = n.x - nodeW / 2;
      const y = n.y - nodeH / 2;
      drawBox(svg, x, y, nodeW, nodeH, st);
      drawLabel(svg, n.x, n.y - 1, n.id, {
        size: 11, anchor: 'middle', mono: true, weight: 600,
        fill: n.tier === 'deciduous' ? COLORS.terracotta
          : (n.tier === 'integrated' ? COLORS.sage : COLORS.ink)
      });
      drawLabel(svg, n.x, n.y + 12, n.role, {
        size: 9, anchor: 'middle', fill: COLORS.muted
      });
    });

    // Legend
    const lx = 20;
    const ly = H - 90;
    drawLabel(svg, lx, ly, 'tiers', { size: 11, weight: 700, fill: COLORS.muted });
    const tiers = [
      ['substrate',  COLORS.ink,         'the codebase under examination'],
      ['integrated', COLORS.sage,        'present in this checkout (submodule/dir)'],
      ['reference',  COLORS.ink,         'discoverable, not integrated'],
      ['mentioned',  COLORS.soft,        'named in docs/diary, unread'],
      ['deciduous',  COLORS.terracotta,  'third-party tool used here']
    ];
    tiers.forEach((t, i) => {
      const yy = ly + 14 + i * 14;
      svg.append('rect')
        .attr('x', lx).attr('y', yy - 8)
        .attr('width', 16).attr('height', 10)
        .attr('fill', 'none')
        .attr('stroke', t[1])
        .attr('stroke-width', 1.25);
      drawLabel(svg, lx + 22, yy, t[0], { size: 10, mono: true, weight: 600 });
      drawLabel(svg, lx + 110, yy, t[2], { size: 10, fill: COLORS.muted });
    });
  }

  // ---------- Diagram 5: Agent fleet ----------

  function renderAgentFleet(sel) {
    const container = getContainer(sel);
    if (!container) return;

    const W = 780;
    const H = 520;
    const svg = makeSvg(container, W, H);

    const columns = [
      {
        title: 'CONVERSATIONAL',
        color: COLORS.sage,
        agents: [
          { name: 'Alpha',     role: 'the duck · memory=project · default' },
          { name: 'Answertron',role: 'opus · WebSearch + fetch + WebFetch' },
          { name: 'Librarian', role: 'opus · llms.txt table for 12 services' }
        ]
      },
      {
        title: 'CUSTODIAL',
        color: COLORS.muted,
        agents: [
          { name: 'Edgar',         role: 'Postgres DBA on memorybanks · opus' },
          { name: 'Lazlo',         role: 'object storage on warehouse13 · opus' },
          { name: 'Mac',           role: 'technician on Jeffery’s MacBook · opus' },
          { name: 'Operator/Link', role: 'Primer: ZFS + libvirt + Docker · inherit' }
        ]
      },
      {
        title: 'UTILITY',
        color: COLORS.terracotta,
        agents: [
          { name: 'Programmer', role: 'code generation · opus' },
          { name: 'Researcher', role: 'WebSearch + WebFetch · haiku' }
        ]
      }
    ];

    const colGap = 12;
    const colW = (W - 40 - colGap * 2) / 3;
    const colTop = 70;
    const cardH = 56;
    const cardGap = 12;

    // Header
    drawLabel(svg, 20, 26, 'agents under .claude/agents/', {
      size: 13, weight: 700
    });
    drawLabel(svg, 20, 42, 'three registers, three columns, one settings.json', {
      size: 11, fill: COLORS.muted
    });

    columns.forEach((col, ci) => {
      const x = 20 + ci * (colW + colGap);
      // column header
      drawLabel(svg, x + colW / 2, colTop - 14, col.title, {
        size: 11, anchor: 'middle', weight: 700, fill: col.color
      });
      // header underline
      svg.append('line')
        .attr('x1', x).attr('y1', colTop - 4)
        .attr('x2', x + colW).attr('y2', colTop - 4)
        .attr('stroke', col.color)
        .attr('stroke-width', 1);

      col.agents.forEach((a, ai) => {
        const y = colTop + 6 + ai * (cardH + cardGap);
        // card-stack effect: thin offset shadow rect
        drawBox(svg, x + 3, y + 3, colW, cardH, {
          stroke: COLORS.soft, fill: 'none'
        });
        drawBox(svg, x, y, colW, cardH, {
          stroke: col.color, fill: COLORS.cream
        });
        drawLabel(svg, x + 12, y + 22, a.name, {
          size: 13, weight: 700, fill: col.color
        });
        drawLabel(svg, x + 12, y + 42, a.role, {
          size: 10, fill: COLORS.ink, mono: true
        });
      });

      // vertical divider between columns
      if (ci < columns.length - 1) {
        svg.append('line')
          .attr('x1', x + colW + colGap / 2)
          .attr('y1', colTop - 20)
          .attr('x2', x + colW + colGap / 2)
          .attr('y2', H - 60)
          .attr('stroke', COLORS.soft)
          .attr('stroke-width', 0.75)
          .attr('stroke-dasharray', '2,3');
      }
    });

    // Footnote
    drawLabel(svg, 20, H - 30,
      'Custodial agents come from the agent-fleet plugin marketplace.', {
        size: 11, fill: COLORS.muted
      });
    drawLabel(svg, 20, H - 14,
      'Utility agents arrive via Loom-dotclaude; Conversational agents are Alpha-native.', {
        size: 11, fill: COLORS.muted
      });
  }

  // ---------- Diagram 6: Decision graph (force-directed) ----------

  function renderDecisionGraph(sel) {
    const container = getContainer(sel);
    if (!container) return;

    const W = 800;
    const H = 500;
    const svg = makeSvg(container, W, H);

    const message = svg.append('g')
      .attr('class', 'dg-message');

    function showFallback(text) {
      message.append('text')
        .attr('x', W / 2)
        .attr('y', H / 2)
        .attr('text-anchor', 'middle')
        .attr('font-family', FONT_SANS)
        .attr('font-size', 12)
        .attr('fill', COLORS.muted)
        .text(text);
    }

    function styleForNode(n) {
      const type = (n.type || '').toLowerCase();
      const status = (n.status || '').toLowerCase();
      switch (type) {
        case 'goal':
          return { kind: 'circle', r: 7, fill: COLORS.sage, stroke: COLORS.sage };
        case 'option': {
          const light = status === 'rejected';
          return {
            kind: 'ring',
            r: 5,
            fill: 'none',
            stroke: light ? COLORS.soft : COLORS.muted,
            strikethrough: status === 'superseded'
          };
        }
        case 'decision':
          return { kind: 'diamond', r: 6, fill: COLORS.ink, stroke: COLORS.ink };
        case 'action':
          return { kind: 'circle', r: 4, fill: COLORS.muted, stroke: COLORS.muted };
        case 'outcome':
          return { kind: 'circle', r: 5, fill: COLORS.terracotta, stroke: COLORS.terracotta };
        case 'observation':
          return { kind: 'circle', r: 3, fill: COLORS.soft, stroke: COLORS.soft };
        case 'revisit':
          return { kind: 'diamond', r: 6, fill: COLORS.terracotta, stroke: COLORS.terracotta };
        default:
          return { kind: 'circle', r: 4, fill: COLORS.muted, stroke: COLORS.muted };
      }
    }

    fetch('graph-data.json')
      .then(r => {
        if (!r.ok) throw new Error('graph-data.json not ok: ' + r.status);
        return r.json();
      })
      .then(raw => {
        // Tolerate a couple of shapes
        let rawNodes = raw.nodes || raw.Nodes || [];
        let rawLinks = raw.links || raw.edges || raw.Edges || [];

        if (!Array.isArray(rawNodes) || rawNodes.length === 0) {
          showFallback('decision graph: no nodes in graph-data.json');
          return;
        }

        const nodes = rawNodes.map(n => {
          return {
            id: String(n.id),
            type: n.type || n.kind || 'observation',
            status: n.status || '',
            title: n.title || n.label || n.id || ''
          };
        });
        const idSet = new Set(nodes.map(n => n.id));

        const links = rawLinks
          .map(l => {
            const s = String(l.source || l.from || l.src || '');
            const t = String(l.target || l.to || l.dst || '');
            return { source: s, target: t };
          })
          .filter(l => idSet.has(l.source) && idSet.has(l.target));

        const link = svg.append('g')
          .attr('stroke', COLORS.soft)
          .attr('stroke-width', 0.75)
          .selectAll('line')
          .data(links)
          .enter()
          .append('line');

        const nodeG = svg.append('g')
          .selectAll('g')
          .data(nodes)
          .enter()
          .append('g')
          .attr('class', 'dg-node');

        nodeG.each(function (n) {
          const s = styleForNode(n);
          const g = d3.select(this);
          if (s.kind === 'circle') {
            g.append('circle')
              .attr('r', s.r)
              .attr('fill', s.fill)
              .attr('stroke', s.stroke)
              .attr('stroke-width', 1);
          } else if (s.kind === 'ring') {
            g.append('circle')
              .attr('r', s.r)
              .attr('fill', 'none')
              .attr('stroke', s.stroke)
              .attr('stroke-width', 1.25);
            if (s.strikethrough) {
              g.append('line')
                .attr('x1', -s.r - 1).attr('y1', 0)
                .attr('x2',  s.r + 1).attr('y2', 0)
                .attr('stroke', s.stroke)
                .attr('stroke-width', 1);
            }
          } else if (s.kind === 'diamond') {
            const r = s.r;
            g.append('polygon')
              .attr('points', [
                [0, -r].join(','),
                [r, 0].join(','),
                [0, r].join(','),
                [-r, 0].join(',')
              ].join(' '))
              .attr('fill', s.fill)
              .attr('stroke', s.stroke)
              .attr('stroke-width', 1);
          }
          g.append('title').text(
            (n.title || '(untitled)') + '  ·  ' + (n.type || 'node')
          );
        });

        const sim = d3.forceSimulation(nodes)
          .force('link', d3.forceLink(links).id(d => d.id).distance(40).strength(0.7))
          .force('charge', d3.forceManyBody().strength(-90))
          .force('center', d3.forceCenter(W / 2, H / 2))
          .force('collide', d3.forceCollide().radius(10))
          .alpha(0.9)
          .alphaDecay(0.04);

        sim.on('tick', () => {
          link
            .attr('x1', d => d.source.x)
            .attr('y1', d => d.source.y)
            .attr('x2', d => d.target.x)
            .attr('y2', d => d.target.y);
          nodeG.attr('transform', d => `translate(${d.x},${d.y})`);
        });

        // Legend in corner
        const legend = [
          ['goal',        COLORS.sage,        'circle'],
          ['option',      COLORS.muted,       'ring'],
          ['decision',    COLORS.ink,         'diamond'],
          ['action',      COLORS.muted,       'small'],
          ['outcome',     COLORS.terracotta,  'circle'],
          ['observation', COLORS.soft,        'tiny'],
          ['revisit',     COLORS.terracotta,  'diamond']
        ];
        const lg = svg.append('g').attr('transform', `translate(12, 12)`);
        lg.append('rect')
          .attr('width', 140).attr('height', legend.length * 16 + 12)
          .attr('fill', COLORS.cream)
          .attr('stroke', COLORS.soft)
          .attr('stroke-width', 0.75);
        legend.forEach((l, i) => {
          const y = 14 + i * 16;
          lg.append('circle')
            .attr('cx', 14).attr('cy', y - 4)
            .attr('r', 4)
            .attr('fill', l[2] === 'ring' ? 'none' : l[1])
            .attr('stroke', l[1])
            .attr('stroke-width', 1.25);
          lg.append('text')
            .attr('x', 26).attr('y', y)
            .attr('font-family', FONT_SANS)
            .attr('font-size', 11)
            .attr('fill', COLORS.ink)
            .text(l[0]);
        });
      })
      .catch(err => {
        console.warn('renderDecisionGraph: fetch failed', err);
        showFallback(
          'decision graph: open via local server or view docs/index.html'
        );
      });
  }

  // ---------- bootstrap ----------

  document.addEventListener('DOMContentLoaded', function () {
    if (typeof d3 === 'undefined') {
      console.error('findings.diagrams: d3 v7 must be loaded before this file');
      return;
    }
    renderArchitecture('#diagram-architecture');
    renderHookFlow('#diagram-hook-flow');
    renderRecallPipeline('#diagram-recall');
    renderEcosystem('#diagram-ecosystem');
    renderAgentFleet('#diagram-agents');
    renderDecisionGraph('#diagram-decisions');
  });
})();
