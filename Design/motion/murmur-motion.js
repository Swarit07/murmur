/*
 * Murmur motion components, mounted on the boards with
 *   <x-import component-from-global-scope="MurmurWave" from="./murmur-motion.js" ...>
 *
 * MurmurWave   w, h, color, still ("true"), level (0..1)
 *              The logo's tail as a live waveform: rounded lobes, top at 100%,
 *              bottom at 82%, tapering to a 0.7pt hairline on the right.
 * MurmurDots   size, color          Five dots rippling left to right (processing).
 * MurmurRing   size, duration, color  Countdown ring that drains over `duration` s.
 * MurmurLevels bars, h, bar-w, color, accent  Mic test level meter.
 *
 * Everything idles to a still frame under prefers-reduced-motion.
 */
(function () {
  function R() { return window.React; }
  function num(v, d) { var n = parseFloat(v); return isFinite(n) ? n : d; }
  function bool(v) { return v === true || v === 'true' || v === ''; }
  function reduced() {
    try { return window.matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) { return false; }
  }

  /* one shared animation loop for every component on the board */
  var subs = [];
  var raf = 0;
  function loop(now) {
    for (var i = 0; i < subs.length; i++) subs[i](now);
    raf = subs.length ? requestAnimationFrame(loop) : 0;
  }
  function subscribe(fn) {
    subs.push(fn);
    if (!raf) raf = requestAnimationFrame(loop);
    return function () {
      var i = subs.indexOf(fn);
      if (i >= 0) subs.splice(i, 1);
    };
  }

  function clamp(x, a, b) { return x < a ? a : x > b ? b : x; }
  function smooth(e0, e1, x) { var t = clamp((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t); }

  /* a believable speaking level: syllable pulses, phrase swells, short pauses */
  function speech(t, seed) {
    var syll = Math.pow(Math.max(0, Math.sin(t * 7.1 + seed * 3.1)), 2);
    var phrase = 0.5 + 0.5 * Math.sin(t * 1.3 + seed);
    var gate = smooth(-0.95, -0.7, Math.sin(t * 0.9 + seed * 1.7));
    return clamp(gate * (0.28 + 0.5 * syll + 0.22 * phrase), 0, 1);
  }

  function lobeHeight(k, t, salt) {
    var a = Math.sin(k * 12.9898 + salt * 78.233) * 43758.5453;
    var r = a - Math.floor(a);
    return 0.3 + 0.7 * (0.5 + 0.5 * Math.sin(t * (1.6 + r * 2.2) + r * 6.283));
  }

  function drawWave(ctx, w, h, t, level, color) {
    ctx.clearRect(0, 0, w, h);
    var mid = h / 2;
    var hair = 0.35;
    var amp = Math.max(0, h / 2 - 0.75);
    var lobes = Math.max(4, w / 15);
    var n = Math.max(48, Math.round(w * 1.5));
    var drift = t * 2.4;
    var gain = clamp(level, 0, 1);
    var top = [];
    var bot = [];
    for (var i = 0; i <= n; i++) {
      var u = i / n;
      var x = u * w;
      var rise = u < 0.14 ? Math.sin((u / 0.14) * Math.PI / 2) : 1;
      var fall = u < 0.42 ? 1 : Math.pow(1 - (u - 0.42) / 0.58, 1.35);
      var env = rise * fall;
      var p = u * lobes * Math.PI - drift;
      var k = Math.floor(p / Math.PI);
      var s = Math.sin(p - k * Math.PI);
      var lobe = Math.pow(s, 1.2);
      var up = hair + amp * gain * env * lobeHeight(k, t, 1) * lobe;
      var dn = hair + 0.82 * amp * gain * env * lobeHeight(k, t, 2) * lobe;
      top.push([x, mid - up]);
      bot.push([x, mid + dn]);
    }
    ctx.beginPath();
    ctx.moveTo(top[0][0], top[0][1]);
    for (var j = 1; j < top.length; j++) ctx.lineTo(top[j][0], top[j][1]);
    for (var m = bot.length - 1; m >= 0; m--) ctx.lineTo(bot[m][0], bot[m][1]);
    ctx.closePath();
    ctx.fillStyle = color;
    ctx.fill();
  }

  function MurmurWave(props) {
    var React = R();
    var ref = React.useRef(null);
    var w = num(props.w, 112);
    var h = num(props.h, 22);
    var color = props.color || '#1F1E1D';
    var still = bool(props.still);
    var level = num(props.level, 0.6);
    React.useEffect(function () {
      var c = ref.current;
      if (!c) return undefined;
      var dpr = Math.max(1, Math.min(3, window.devicePixelRatio || 1));
      c.width = Math.round(w * dpr);
      c.height = Math.round(h * dpr);
      var ctx = c.getContext('2d');
      var seed = Math.random() * 20;
      function paint(t, lv) {
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        drawWave(ctx, w, h, t, lv, color);
      }
      if (still || reduced()) {
        paint(seed + 1.3, still ? clamp(level, 0, 1) : 0.8);
        return undefined;
      }
      var t0 = performance.now();
      var cur = 0;
      return subscribe(function (now) {
        var t = (now - t0) / 1000 + seed;
        var target = speech(t, seed);
        cur += (target - cur) * (target > cur ? 0.3 : 0.09);
        paint(t, Math.min(1, cur * 2.1));
      });
    }, [w, h, color, still, level]);
    return React.createElement('canvas', {
      ref: ref,
      'aria-hidden': 'true',
      style: { width: w + 'px', height: h + 'px', display: 'block', flex: 'none' }
    });
  }

  function MurmurDots(props) {
    var React = R();
    var size = num(props.size, 5);
    var color = props.color || '#F6EEE4';
    var gap = size * 0.75;
    var refs = [React.useRef(null), React.useRef(null), React.useRef(null), React.useRef(null), React.useRef(null)];
    React.useEffect(function () {
      function place(t) {
        for (var i = 0; i < 5; i++) {
          var el = refs[i].current;
          if (!el) continue;
          var ph = Math.max(0, Math.sin((t / 1.1) * 2 * Math.PI - i * 0.62));
          el.style.transform = 'translateY(' + (-ph * size * 0.9).toFixed(2) + 'px)';
          el.style.opacity = (0.4 + 0.6 * ph).toFixed(3);
        }
      }
      if (reduced()) { place(0.35); return undefined; }
      var t0 = performance.now();
      return subscribe(function (now) { place((now - t0) / 1000); });
    }, [size]);
    var dots = [];
    for (var i = 0; i < 5; i++) {
      dots.push(React.createElement('span', {
        key: i,
        ref: refs[i],
        style: { width: size + 'px', height: size + 'px', borderRadius: size + 'px', background: color, display: 'block', flex: 'none' }
      }));
    }
    return React.createElement('div', {
      'aria-hidden': 'true',
      style: {
        width: (5 * size + 4 * gap) + 'px', height: (3 * size) + 'px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between', paddingTop: size + 'px', boxSizing: 'border-box', flex: 'none'
      }
    }, dots);
  }

  function MurmurRing(props) {
    var React = R();
    var size = num(props.size, 22);
    var duration = num(props.duration, 5);
    var color = props.color || '#F6EEE4';
    var stroke = 2;
    var r = (size - stroke) / 2;
    var circ = 2 * Math.PI * r;
    var arcRef = React.useRef(null);
    var numRef = React.useRef(null);
    React.useEffect(function () {
      function at(elapsed) {
        var cycle = duration + 0.8;
        var e = elapsed % cycle;
        var left = clamp(1 - e / duration, 0, 1);
        if (arcRef.current) arcRef.current.setAttribute('stroke-dashoffset', (circ * (1 - left)).toFixed(2));
        if (numRef.current) numRef.current.textContent = String(Math.max(0, Math.ceil(left * duration)));
      }
      if (reduced()) { at(duration * 0.35); return undefined; }
      var t0 = performance.now();
      return subscribe(function (now) { at((now - t0) / 1000); });
    }, [size, duration]);
    var c = size / 2;
    return React.createElement('svg', {
      width: size, height: size, viewBox: '0 0 ' + size + ' ' + size, 'aria-hidden': 'true', style: { display: 'block', flex: 'none' }
    },
      React.createElement('circle', { cx: c, cy: c, r: r, fill: 'none', stroke: color, strokeOpacity: 0.22, strokeWidth: stroke }),
      React.createElement('circle', {
        ref: arcRef, cx: c, cy: c, r: r, fill: 'none', stroke: color, strokeWidth: stroke, strokeLinecap: 'round',
        strokeDasharray: circ.toFixed(2), strokeDashoffset: 0, transform: 'rotate(-90 ' + c + ' ' + c + ')'
      }),
      React.createElement('text', {
        ref: numRef, x: c, y: c, textAnchor: 'middle', dominantBaseline: 'central', fill: color,
        style: { font: '500 ' + Math.round(size * 0.42) + 'px "Geist Mono", ui-monospace, monospace' }
      }, String(duration))
    );
  }

  function MurmurLevels(props) {
    var React = R();
    var bars = Math.round(num(props.bars, 18));
    var h = num(props.h, 64);
    var bw = num(props.barW, num(props['bar-w'], 8));
    var gap = Math.max(2, bw / 2);
    var color = props.color || '#1F1E1D';
    var accent = props.accent || '#B54C3C';
    var refs = React.useRef([]);
    React.useEffect(function () {
      var seed = Math.random() * 20;
      var cur = 0;
      function paint(level) {
        var lit = level * bars;
        for (var i = 0; i < bars; i++) {
          var el = refs.current[i];
          if (!el) continue;
          var on = i < lit;
          el.style.background = on ? (i >= bars * 2 / 3 ? accent : color) : 'rgba(31,30,29,0.12)';
        }
      }
      if (reduced()) { paint(0.72); return undefined; }
      var t0 = performance.now();
      return subscribe(function (now) {
        var t = (now - t0) / 1000 + seed;
        var target = 0.15 + 0.85 * speech(t, seed);
        cur += (target - cur) * (target > cur ? 0.35 : 0.08);
        paint(cur);
      });
    }, [bars, h, bw, color, accent]);
    var kids = [];
    for (var i = 0; i < bars; i++) {
      var bh = h * (0.3 + 0.7 * Math.pow(i / Math.max(1, bars - 1), 0.85));
      kids.push(React.createElement('span', {
        key: i,
        ref: (function (idx) { return function (el) { refs.current[idx] = el; }; })(i),
        style: { width: bw + 'px', height: bh.toFixed(1) + 'px', borderRadius: Math.min(4, bw / 2) + 'px', background: 'rgba(31,30,29,0.12)', display: 'block', flex: 'none' }
      }));
    }
    return React.createElement('div', {
      'aria-hidden': 'true',
      style: { height: h + 'px', display: 'flex', alignItems: 'flex-end', gap: gap + 'px', flex: 'none' }
    }, kids);
  }

  window.MurmurWave = MurmurWave;
  window.MurmurDots = MurmurDots;
  window.MurmurRing = MurmurRing;
  window.MurmurLevels = MurmurLevels;
})();
