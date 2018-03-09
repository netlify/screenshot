const puppeteer = require("puppeteer");
const http = require("http");
const { URLSearchParams } = require("url");

let browser;

const server = http.createServer(async (req, res) => {
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
    await Promise.all(
      page.frames().map(frame => {
        return frame
          .evaluate(() => {
            document.querySelectorAll("video, audio").forEach(m => {
              if (!m) return;
              if (m.pause) m.pause();
              m.preload = "none";
            });
          })
          .catch(err => {}); // swallow errors
      })
    );

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
    const { message = "", stack = "" } = e;
    res.writeHead(500, {
      "content-type": "text/plain"
    });
    res.end(`Error generating screenshot.\n\n${message}\n\n${stack}`);

    const duration = Date.now() - start;
    console.log(`url=${url} timing=${duration} status=500 error="${message}"`);
  } finally {
    if (page) {
      page.removeAllListeners();
      try {
        const cookies = await page.cookies();
        await page.deleteCookie(...cookies);
        // tip from https://github.com/GoogleChrome/puppeteer/issues/1490
        await page.goto("about:blank", { timeout: 1000 }).catch(err => {});
      } catch (ex) {
        // intentionally empty
      } finally {
        page.close().catch(err => {});
        page = null;
      }
    }
  }
});

console.log("Launching Chrome");
const config = {
  ignoreHTTPSErrors: true,
  args: [
    "--no-sandbox",
    "--disable-setuid-sandbox",
    "--disable-gpu",
    '--js-flags="--max_old_space_size=500"'
  ],
  executablePath: process.env.CHROME_BIN
};
puppeteer
  .launch(config)
  .then(b => {
    browser = b;
    const port = process.env.PORT || 3001;
    server.listen(port, () => {
      console.log(`listening on port ${port}`);
    });
  })
  .catch(err => {
    console.error("Error launching chrome: ", err);
    process.exit(1);
  });

const stopServer = async () => {
  server.close(() => {
    process.exit();
  });
};
process.on("SIGINT", stopServer);
process.on("SIGTERM", stopServer);

process.on("unhandledRejection", (reason, p) => {
  console.log("Unhandled Rejection at:", p, "reason:", reason);
});
