/**
 * WebPage.ets - 浏览器访问的控制/观看页 HTML
 * 由 HttpServer 在 GET / 时返回。极简单页：内嵌 MJPEG 流 + 快照 + 状态。
 */
export class WebPage {
  static html(deviceLabel: string): string {
    return `<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>IP Webcam · ${deviceLabel}</title>
<style>
  :root { --bg:#0B0F0C; --card:#151C17; --line:#243027; --fg:#EAF2EC; --dim:#8FA394; --accent:#2ECC71; }
  * { box-sizing:border-box; margin:0; }
  body { background:var(--bg); color:var(--fg); font:15px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif; }
  header { padding:16px 20px; border-bottom:1px solid var(--line); display:flex; align-items:center; gap:10px; }
  .dot { width:9px; height:9px; border-radius:50%; background:var(--accent); box-shadow:0 0 10px var(--accent); }
  header b { font-weight:600; letter-spacing:.02em; }
  header span { color:var(--dim); font-size:13px; }
  main { max-width:900px; margin:0 auto; padding:20px; }
  .frame { background:#000; border:1px solid var(--line); border-radius:12px; overflow:hidden; line-height:0; }
  .frame img { width:100%; display:block; }
  .bar { display:flex; gap:10px; flex-wrap:wrap; margin-top:14px; }
  a.btn, button.btn { appearance:none; border:1px solid var(--line); background:var(--card); color:var(--fg);
    padding:10px 16px; border-radius:10px; font-size:14px; cursor:pointer; text-decoration:none; }
  a.btn:hover, button.btn:hover { border-color:var(--accent); }
  .btn.primary { background:var(--accent); color:#06210F; border-color:var(--accent); font-weight:600; }
  footer { color:var(--dim); font-size:12px; text-align:center; padding:18px; }
  code { background:var(--card); padding:2px 6px; border-radius:6px; color:var(--accent); }
</style>
</head>
<body>
  <header>
    <span class="dot"></span><b>IP Webcam</b><span>· ${deviceLabel}</span>
  </header>
  <main>
    <div class="frame"><img src="/video" alt="live stream"></div>
    <div class="bar">
      <a class="btn primary" href="/video" target="_blank">全屏视频流</a>
      <a class="btn" href="/shot.jpg" target="_blank">抓取快照</a>
      <button class="btn" onclick="location.reload()">重新连接</button>
    </div>
    <p style="color:var(--dim);margin-top:16px;font-size:13px;">
      直接在 VLC / ffplay / 监控软件中打开 <code>/video</code>（MJPEG）或 <code>/shot.jpg</code>（单帧）。
    </p>
  </main>
  <footer>Served by IP Webcam for HarmonyOS</footer>
</body>
</html>`;
  }
}
