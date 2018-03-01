const puppeteer = require("puppeteer");
const http = require("http");
const { URLSearchParams } = require("url");

let browser;

http
  .createServer(async (req, res) => {
    let page, start, url;

    try {
      const { host } = req.headers;
      const searchParams = new URLSearchParams(req.url.slice(1));
      url = searchParams.get("url");
      const width = parseInt(searchParams.get("width"), 10) || 1024;
      const height = parseInt(searchParams.get("height"), 10) || 600;
      const delay = searchParams.get("delay") || 0;
      const clipRect = searchParams.get("clipRect");
      let clip;
      if (clipRect) {
        cr = JSON.parse(clipRect);
        clip = {
          x: cr.left || 0,
          y: cr.top || 0,
          width: cr.width || width,
          height: cr.height || height
        };
      }

      if (!browser) {
        console.log("Launching Chrome");
        const config = {
          ignoreHTTPSErrors: true,
          args: ["--no-sandbox", "--disable-setuid-sandbox"]
        };
        browser = await puppeteer.launch(config);
      }
      page = await browser.newPage();

      start = Date.now();
      let reqCount = 0;

      const responsePromise = new Promise((resolve, reject) => {
        page.on("response", ({ headers }) => {
          const location = headers["location"];
          if (location && location.includes(host)) {
            reject(new Error("Possible infinite redirects detected."));
          }
        });
      });

      await page.setViewport({
        width,
        height
      });

      await Promise.race([
        responsePromise,
        page.goto(url, {
          waitUntil: "load"
        })
      ]);
      await new Promise(resolve => setTimeout(resolve, delay));

      // Pause all media and stop buffering
      page.frames().forEach(frame => {
        frame.evaluate(() => {
          document.querySelectorAll("video, audio").forEach(m => {
            if (!m) return;
            if (m.pause) m.pause();
            m.preload = "none";
          });
        });
      });

      const screenshot = await page.screenshot({
        type: "png",
        fullPage: false,
        clip
      });

      res.writeHead(200, {
        "content-type": "image/png",
        "cache-control": "public,max-age=31536000"
      });
      res.end(screenshot, "binary");

      const duration = Date.now() - start;
      const clipstr = (clip && JSON.stringify(clip)) || "none";
      console.log(
        `url=${url} timing=${duration} size=${
          screenshot.length
        } status=200 width=${width} height=${height} delay=${delay} clip="${clipstr}"`
      );
    } catch (e) {
      const { message = "" } = e;
      res.writeHead(500, {
        "content-type": "text/plain"
      });
      res.end("Error generating screenshot.\n\n" + message);

      const duration = Date.now() - start;
      console.log(
        `url=${url} timing=${duration} status=500 error="${message}"`
      );

      // Handle websocket not opened error
      if (/not opened/i.test(message) && browser) {
        console.error("chrome web socket failed");
        try {
          page.removeAllListeners();
          page.close();
          page = null;
          browser.close();
          browser = null;
        } catch (err) {
          console.warn(`chrome could not be killed ${err.message}`);
          browser = null;
        }
      }
    } finally {
      if (page) {
        page.removeAllListeners();
        page.close();
        page = null;
      }
    }
  })
  .listen(process.env.PORT || 3001);

process.on("SIGINT", () => {
  if (browser) browser.close();
  process.exit();
});

process.on("unhandledRejection", (reason, p) => {
  console.log("Unhandled Rejection at:", p, "reason:", reason);
});
