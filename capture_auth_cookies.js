#!/usr/bin/env node
'use strict';

const fs = require('node:fs/promises');
const path = require('node:path');
const readline = require('node:readline/promises');
const { stdin: input, stdout: output } = require('node:process');
const { chromium } = require('playwright-core');

const DEFAULT_URL =
  'https://authserver-443.vpn5.szpu.edu.cn/authserver/login?type=dynamicLogin&service=https%3A%2F%2Fjwxt-443.vpn5.szpu.edu.cn%2Fjwapp%2Fsys%2FxsdgsxbmMobile%2F*default%2Findex.do%23%2Fckqdxx';

function parseArgs(argv) {
  const args = {
    url: DEFAULT_URL,
    out: path.resolve(process.cwd(), '.auth_cookies'),
    browser: 'msedge',
  };

  for (let i = 0; i < argv.length; i += 1) {
    const value = argv[i];

    if (value === '--help' || value === '-h') {
      args.help = true;
    } else if (value === '--url') {
      args.url = argv[++i];
    } else if (value === '--out') {
      args.out = path.resolve(argv[++i]);
    } else if (value === '--browser') {
      args.browser = argv[++i];
    } else {
      throw new Error(`未知参数：${value}`);
    }
  }

  return args;
}

function printHelp() {
  console.log(`
用法：
  node capture_auth_cookies.js
  node capture_auth_cookies.js --browser chrome
  node capture_auth_cookies.js --out .auth_cookies

流程：
  1. 脚本打开浏览器并进入统一认证页面
  2. 你在浏览器里手动登录、完成验证码或跳转
  3. 回到终端按 Enter
  4. 脚本保存当前浏览器上下文里的 Cookie

参数：
  --url       要打开的登录地址
  --out       Cookie 保存目录，默认 .auth_cookies
  --browser   msedge、chrome、chrome-beta、msedge-beta 等 Playwright 支持的 channel
`.trim());
}

function cookieAppliesToHost(cookie, host) {
  const domain = cookie.domain.replace(/^\./, '').toLowerCase();
  const normalizedHost = host.toLowerCase();
  return normalizedHost === domain || normalizedHost.endsWith(`.${domain}`);
}

function normalizeCookieHeader(cookies, host) {
  return cookies
    .filter((cookie) => cookieAppliesToHost(cookie, host))
    .map((cookie) => `${cookie.name}=${cookie.value}`)
    .join('; ');
}

async function ensureGitignore(outDir) {
  const gitignorePath = path.resolve(process.cwd(), '.gitignore');
  const relativeOut = path.relative(process.cwd(), outDir).replaceAll('\\', '/');
  const rule = `/${relativeOut}/`;

  let content = '';
  try {
    content = await fs.readFile(gitignorePath, 'utf8');
  } catch (error) {
    if (error.code !== 'ENOENT') {
      throw error;
    }
  }

  if (!content.split(/\r?\n/).includes(rule)) {
    const nextContent =
      content && !content.endsWith('\n') ? `${content}\n${rule}\n` : `${content}${rule}\n`;
    await fs.writeFile(gitignorePath, nextContent, 'utf8');
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help) {
    printHelp();
    return;
  }

  await fs.mkdir(args.out, { recursive: true });
  await ensureGitignore(args.out);

  const userDataDir = path.join(args.out, 'browser-profile');
  console.log(`正在打开浏览器：${args.browser}`);
  const context = await chromium.launchPersistentContext(userDataDir, {
    channel: args.browser,
    headless: false,
    viewport: null,
  });

  const page = context.pages()[0] ?? await context.newPage();
  page.setDefaultNavigationTimeout(30000);

  const rl = readline.createInterface({ input, output });
  console.log('浏览器已打开，正在进入登录页。');
  try {
    await page.goto(args.url, { waitUntil: 'domcontentloaded', timeout: 30000 });
  } catch (error) {
    console.log(`登录页加载未完成：${error.message}`);
    console.log('浏览器窗口仍然可用，你可以手动刷新或粘贴登录地址继续。');
  }

  console.log('请在浏览器里完成登录/滑块/跳转。');
  console.log('完成后回到这个终端按 Enter，脚本会保存 Cookie。');
  await rl.question('完成后按 Enter 保存 Cookie...');
  rl.close();

  const cookies = await context.cookies();
  const savedAt = new Date().toISOString();
  const payload = {
    savedAt,
    currentUrl: page.url(),
    cookies,
  };

  const jsonPath = path.join(args.out, 'cookies.json');
  const authHeaderPath = path.join(args.out, 'authserver-cookie-header.txt');
  const jwxtHeaderPath = path.join(args.out, 'jwxt-cookie-header.txt');
  const allHeaderPath = path.join(args.out, 'all-cookie-header.txt');

  const authserverHeader = normalizeCookieHeader(cookies, 'authserver-443.vpn5.szpu.edu.cn');
  const jwxtHeader = normalizeCookieHeader(cookies, 'jwxt-443.vpn5.szpu.edu.cn');
  const allHeader = cookies.map((cookie) => `${cookie.name}=${cookie.value}`).join('; ');

  await fs.writeFile(jsonPath, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
  await fs.writeFile(authHeaderPath, `${authserverHeader}\n`, 'utf8');
  await fs.writeFile(jwxtHeaderPath, `${jwxtHeader}\n`, 'utf8');
  await fs.writeFile(allHeaderPath, `${allHeader}\n`, 'utf8');

  console.log(`已保存：${jsonPath}`);
  console.log(`认证域 Cookie 请求头：${authHeaderPath}`);
  console.log(`教务域 Cookie 请求头：${jwxtHeaderPath}`);
  console.log(`全部 Cookie 请求头：${allHeaderPath}`);
  console.log('这些文件包含登录态，请不要发给别人。');

  await context.close();
}

main().catch((error) => {
  console.error(`错误：${error.message}`);
  process.exitCode = 1;
});
