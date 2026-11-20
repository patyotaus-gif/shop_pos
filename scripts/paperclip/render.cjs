// Copy beside the Paperclip marketing toolkit's package.json on the rendering host.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const {bundle} = require('@remotion/bundler');
const {selectComposition, renderMedia} = require('@remotion/renderer');

async function main() {
  const [entry, id, output] = process.argv.slice(2);
  if (!entry || !id || !output) {
    throw new Error('Usage: node render.cjs <entry.jsx> <composition ID> <output.mp4>');
  }

  const bundleDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pokpok-reel-'));
  try {
    const serveUrl = await bundle({
      entryPoint: path.resolve(entry),
      outDir: bundleDir,
      enableCaching: false,
      // The agent writes JSX in its workspace. Dependencies live in the toolkit.
      webpackOverride: (config) => ({
        ...config,
        resolve: {
          ...config.resolve,
          modules: [path.join(__dirname, 'node_modules'), ...(config.resolve.modules ?? [])],
        },
      }),
    });
    const browserExecutable = process.env.POKPOK_RENDER_BROWSER ||
      'C:/Program Files/Google/Chrome/Application/chrome.exe';
    const options = {serveUrl, browserExecutable, binariesDirectory: path.join(__dirname, 'render-binaries')};
    const composition = await selectComposition({...options, id});
    await renderMedia({
      ...options,
      composition,
      codec: 'h264-mkv',
      audioCodec: 'pcm-16',
      pixelFormat: 'yuv420p',
      concurrency: 1,
      outputLocation: path.join(bundleDir, 'intermediate.mkv'),
    });
    // The standalone Windows build provides native AAC instead of libfdk_aac.
    execFileSync(path.join(options.binariesDirectory, 'ffmpeg.exe'), [
      '-v', 'error', '-y', '-i', path.join(bundleDir, 'intermediate.mkv'),
      '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart',
      '-f', 'mp4', path.resolve(output),
    ]);
  } finally {
    fs.rmSync(bundleDir, {recursive: true, force: true});
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
