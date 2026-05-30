#!/usr/bin/env node
'use strict';

const fs = require('node:fs/promises');
const path = require('node:path');
const readline = require('node:readline/promises');
const { stdin: input, stdout: output } = require('node:process');
const { chromium } = require('playwright-core');

const HOST = 'jwxt-443.vpn5.szpu.edu.cn';
const BASE = `https://${HOST}/jwapp/sys/xsdgsxbmMobile/modules`;
const REFERER_PREFIX = `https://${HOST}/jwapp/sys/xsdgsxbmMobile/*default/index.do#/qddk`;

const LOGIN_URL =
  'https://authserver-443.vpn5.szpu.edu.cn/authserver/login?type=dynamicLogin&service=https%3A%2F%2Fjwxt-443.vpn5.szpu.edu.cn%2Fjwapp%2Fsys%2FxsdgsxbmMobile%2F*default%2Findex.do%23%2Fqddk';

const OUT_DIR = path.resolve(process.cwd(), '.auth_cookies');
const APP_DIR = path.join(
  process.env.APPDATA || process.env.LOCALAPPDATA || process.cwd(),
  'SzpuAttendanceClient',
);
const APP_COOKIE_DIR = path.join(APP_DIR, 'browser_cookies');

function parseArgs(argv) {
  const args = {
    time: null,
    url: LOGIN_URL,
    out: OUT_DIR,
    browser: 'msedge',
    help: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const value = argv[i];
    if (value === '--help' || value === '-h') {
      args.help = true;
    } else if (value === '--time') {
      args.time = argv[++i];
    } else if (value === '--url') {
      args.url = argv[++i];
    } else if (value === '--out') {
      args.out = path.resolve(argv[++i]);
    } else if (value === '--browser') {
      args.browser = argv[++i];
    } else if (value === '--checkin-only') {
      args.checkinOnly = true;
    } else if (value === '--yes' || value === '-y') {
      args.yes = true;
    } else if (value === '--dry-run') {
      args.dryRun = true;
    } else {
      throw new Error(`未知参数：${value}`);
    }
  }

  return args;
}

function printHelp() {
  console.log(`
今日签到脚本 —— 浏览器登录后检查条件并确认提交

用法：
  node auto_checkin.js
  node auto_checkin.js --time 09:00:00
  node auto_checkin.js --browser chrome
  node auto_checkin.js --checkin-only

流程：
  1. 脚本打开浏览器并进入统一认证页面
  2. 你在浏览器里手动登录、完成验证码或跳转
  3. 回到终端按 Enter
  4. 脚本读取配置、检查签到条件、显示提交信息
  5. 输入 y 后提交今日签到

参数：
  --time         指定到岗时间（HH:mm 或 HH:mm:ss），不传则取 config.json 中的值
  --url          要打开的登录地址
  --out          Cookie 保存目录，默认 .auth_cookies
  --browser      msedge、chrome 等 Playwright 支持的 channel
  --checkin-only 跳过浏览器，直接用上一次保存的 Cookie 提交签到
  --dry-run      只检查条件并显示将提交的信息，不真正提交
  --yes, -y      跳过提交前确认
`.trim());
}

function todayStr() {
  const now = chinaNow();
  const y = now.getUTCFullYear();
  const m = String(now.getUTCMonth() + 1).padStart(2, '0');
  const d = String(now.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function currentChinaTime() {
  const now = chinaNow();
  return `${String(now.getUTCHours()).padStart(2, '0')}:` +
    `${String(now.getUTCMinutes()).padStart(2, '0')}:` +
    `${String(now.getUTCSeconds()).padStart(2, '0')}`;
}

function chinaNow() {
  return new Date(Date.now() + 8 * 60 * 60 * 1000);
}

function normalizeTime(value) {
  if (!value) return null;
  const m = /^([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?$/.exec(value.trim());
  if (!m) return null;
  const h = String(Number(m[1])).padStart(2, '0');
  const min = String(Number(m[2])).padStart(2, '0');
  const s = String(Number(m[3] ?? 0)).padStart(2, '0');
  return `${h}:${min}:${s}`;
}

function encodeForm(fields) {
  return Object.entries(fields)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');
}

async function readConfig() {
  const configPath = path.join(APP_DIR, 'config.json');
  let raw;
  try {
    raw = await fs.readFile(configPath, 'utf8');
  } catch (e) {
    throw new Error(`无法读取配置文件：${configPath}\n${e.message}`);
  }
  return JSON.parse(raw);
}

async function readJwxtCookie(outDir) {
  const candidates = [
    path.join(outDir, 'jwxt-cookie-header.txt'),
    path.join(APP_COOKIE_DIR, 'jwxt-cookie-header.txt'),
  ];

  let lastError;
  for (const filePath of candidates) {
    try {
      const cookie = (await fs.readFile(filePath, 'utf8')).trim();
      if (!cookie) throw new Error('Cookie 文件为空');
      return cookie;
    } catch (e) {
      lastError = e;
    }
  }

  throw new Error(
    `无法读取教务 Cookie，已尝试：\n${candidates.join('\n')}\n${lastError?.message ?? ''}`,
  );
}

function decodeJson(raw) {
  let value = JSON.parse(raw);
  if (typeof value === 'string') {
    value = JSON.parse(value);
  }
  return value;
}

function assertNotFutureToday(time) {
  if (time > currentChinaTime()) {
    throw new Error(`到岗时间 ${time} 晚于当前中国时间 ${currentChinaTime()}，请核对后再提交。`);
  }
}

async function confirmSubmit({ args, today, arrivalTime, area, address }) {
  if (args.yes || args.dryRun) return true;

  const rl = readline.createInterface({ input, output });
  try {
    console.log('\n即将提交今日签到，请确认信息真实准确：');
    console.log(`日期时间：${today} ${arrivalTime}`);
    console.log(`所在地：${area}`);
    console.log(`详细地址：${address}`);
    const answer = await rl.question('确认提交请输入 y：');
    return answer.trim().toLowerCase() === 'y';
  } finally {
    rl.close();
  }
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
    if (error.code !== 'ENOENT') throw error;
  }

  if (!content.split(/\r?\n/).includes(rule)) {
    const nextContent =
      content && !content.endsWith('\n') ? `${content}\n${rule}\n` : `${content}${rule}\n`;
    await fs.writeFile(gitignorePath, nextContent, 'utf8');
  }
}

async function saveCookies(outDir, cookies, pageUrl) {
  await fs.mkdir(outDir, { recursive: true });
  const savedAt = new Date().toISOString();

  const jwCookie = normalizeCookieHeader(cookies, HOST);
  const allCookie = cookies.map((c) => `${c.name}=${c.value}`).join('; ');

  await fs.writeFile(
    path.join(outDir, 'cookies.json'),
    `${JSON.stringify({ savedAt, currentUrl: pageUrl, cookies }, null, 2)}\n`,
    'utf8',
  );
  await fs.writeFile(
    path.join(outDir, 'jwxt-cookie-header.txt'),
    `${jwCookie}\n`,
    'utf8',
  );
  await fs.writeFile(
    path.join(outDir, 'all-cookie-header.txt'),
    `${allCookie}\n`,
    'utf8',
  );

  return { jwCookie, allCookie };
}

async function launchBrowserAndCaptureCookies(args) {
  await fs.mkdir(args.out, { recursive: true });
  await ensureGitignore(args.out);

  const userDataDir = path.join(args.out, 'browser-profile');
  console.log(`正在打开浏览器：${args.browser}`);
  const context = await chromium.launchPersistentContext(userDataDir, {
    channel: args.browser,
    headless: false,
    viewport: null,
  });

  const page = context.pages()[0] ?? (await context.newPage());
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
  console.log('完成后回到这个终端按 Enter，脚本会检查今日签到条件。');
  await rl.question('完成后按 Enter 开始检查...');
  rl.close();

  const cookies = await context.cookies();
  const pageUrl = page.url();
  const result = await saveCookies(args.out, cookies, pageUrl);
  await context.close();

  console.log(`已保存 ${cookies.length} 条 Cookie。`);
  return result.jwCookie;
}

async function apiPost(path, body, cookie) {
  const url = `${BASE}/${path}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Accept: 'application/json, text/javascript, */*; q=0.01',
      'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko)',
      'X-Requested-With': 'XMLHttpRequest',
      Cookie: cookie,
      Origin: `https://${HOST}`,
      Referer: REFERER_PREFIX,
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
    },
    body: body || undefined,
  });

  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`HTTP ${res.status}：${text.slice(0, 160)}`);
  }
  return res.text();
}

async function doCheckIn(cookie, config, arrivalTimeOverride, args) {
  const studentId = (config.studentId || '').trim();
  if (!studentId) {
    throw new Error('config.json 中学号为空，请先在应用中设置学号。');
  }

  const area = (config.area || '').trim();
  const address = (config.address || '').trim();
  if (!area || !address) {
    throw new Error('config.json 中签到所在地/详细地址为空，请先在应用中设置。');
  }

  let rawArrivalTime = arrivalTimeOverride || config.arrivalTime || '';
  const arrivalTime = normalizeTime(rawArrivalTime);
  if (!arrivalTime) {
    throw new Error(
      `到岗时间格式无效："${rawArrivalTime}"，应为 HH:mm 或 HH:mm:ss。可通过 --time 参数指定。`,
    );
  }
  assertNotFutureToday(arrivalTime);

  console.log(`\n=== 今日签到 ===`);
  console.log(`学号：${studentId}`);
  console.log(`到岗时间：${arrivalTime}`);
  console.log(`所在地：${area}`);
  console.log(`地址：${address}`);

  // Step 1: 获取实习计划
  console.log('\n[1/4] 查询实习计划...');
  const planResp = await apiPost(
    'qddk/cxjhxs.do',
    encodeForm({ XH: studentId, SXZT: 'sxz' }),
    cookie,
  );
  const planData = decodeJson(planResp);
  const planRow = planData?.datas?.cxjhxs;
  if (!planRow || typeof planRow !== 'object') {
    throw new Error('当前没有实习中的计划，无法签到。');
  }
  const planWid = String(planRow.WID ?? '');
  const schoolYear = String(planRow.XNDM ?? '');
  if (!planWid) {
    throw new Error('未能读取实习计划 WID。');
  }
  console.log(`  计划 WID：${planWid}，学年：${schoolYear}`);

  // Step 2: 检查今日是否已有签到记录
  console.log('[2/4] 检查今日签到记录...');
  const today = todayStr();
  const querySetting = JSON.stringify([
    { name: 'JHXSWID', value: planWid, linkOpt: 'and', builder: 'equal' },
    { name: 'QDSJ', value: today, linkOpt: 'and', builder: 'include' },
  ]);
  const recResp = await apiPost(
    'qddk/cxxsqd.do',
    encodeForm({ querySetting, '*order': '+QDSJ' }),
    cookie,
  );
  const recData = decodeJson(recResp);
  const rows = recData?.datas?.cxxsqd?.rows ?? [];
  if (rows.length > 0) {
    const existing = String(rows[0]?.QDSJ ?? '').slice(0, 19);
    throw new Error(`今天已有签到记录：${existing}`);
  }
  console.log('  今天尚未签到。');

  // Step 3: 检查岗位是否允许签到 + 学年是否开放
  console.log('[3/4] 检查岗位和学年权限...');
  const [postResp, yearResp] = await Promise.all([
    apiPost(
      'qddk/cxjhxszwxx.do',
      encodeForm({ JHXSWID: planWid, SFDQZW: '1' }),
      cookie,
    ),
    apiPost(
      'qddk/gjxndmxycxxtcsxx.do',
      encodeForm({ XNDM: schoolYear }),
      cookie,
    ),
  ]);

  const postData = decodeJson(postResp);
  const postRow = postData?.datas?.cxjhxszwxx ?? {};
  if (!postRow || Object.keys(postRow).length === 0) {
    throw new Error('未查询到当前岗位信息，无法确认是否允许签到。');
  }
  if (String(postRow.ZYSFDK) === '0') {
    throw new Error('当前岗位配置不允许签到。');
  }

  const yearData = decodeJson(yearResp);
  const yearRows = yearData?.datas?.gjxndmxycxxtcsxx?.rows ?? [];
  if (yearRows.length === 0) {
    throw new Error('当前计划学年暂未开放签到，请联系管理员。');
  }
  console.log('  岗位和学年权限检查通过。');

  // Step 4: 提交签到
  console.log('[4/4] 提交签到...');
  const form = {
    JHXSWID: planWid,
    XH: studentId,
    QDSJ: `${today} ${arrivalTime}`,
    QDSZD: area,
    QDXXDZ: address,
    BY1: 'qddk',
    WID: '',
  };
  if (args.dryRun) {
    console.log('\n--dry-run 已启用，只检查条件，不提交签到。');
    console.log(JSON.stringify({ ...form, QDXXDZ: '<已隐藏详细地址>' }, null, 2));
    return;
  }

  const confirmed = await confirmSubmit({ args, today, arrivalTime, area, address });
  if (!confirmed) {
    console.log('\n已取消提交。');
    return;
  }

  const param = encodeForm({ param: JSON.stringify([form]) });
  const submitResp = await apiPost('qddk/bcxsqdxx.do', param, cookie);

  let accepted = false;
  let message = submitResp.slice(0, 160);
  try {
    const submitData = decodeJson(submitResp);
    const ext =
      submitData?.datas?.bcxsqdxx?.extParams ?? submitData?.bcxsqdxx?.extParams ?? {};
    const code = ext.code?.toString();
    const msg = ext.msg?.toString() ?? submitData.msg?.toString() ?? message;
    accepted = code === '1';
    message = msg;
  } catch (_) {
    // 使用原始文本作为消息
  }

  const verifyResp = await apiPost(
    'qddk/cxxsqd.do',
    encodeForm({ querySetting, '*order': '+QDSJ' }),
    cookie,
  );
  const verifyData = decodeJson(verifyResp);
  const verifyRows = verifyData?.datas?.cxxsqd?.rows ?? [];
  const verified = verifyRows.some((row) => String(row?.QDSJ ?? '').startsWith(`${today} `));

  if (accepted || verified) {
    const actual = String(verifyRows[0]?.QDSJ ?? `${today} ${arrivalTime}`).slice(0, 19);
    console.log(`\n✓ 今日签到提交成功：${message}`);
    console.log(`已确认今日签到记录：${actual}`);
  } else {
    console.log(`\n✗ 今日签到提交失败：${message}`);
    process.exitCode = 1;
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help) {
    printHelp();
    return;
  }

  const config = await readConfig();

  let cookie;
  if (args.checkinOnly) {
    cookie = await readJwxtCookie(args.out);
  } else {
    cookie = await launchBrowserAndCaptureCookies(args);
    if (!cookie) {
      throw new Error('未能从浏览器中提取教务 Cookie，请确认已登录并跳转到教务页面。');
    }
  }

  await doCheckIn(cookie, config, args.time, args);
}

main().catch((error) => {
  console.error(`\n错误：${error.message}`);
  process.exitCode = 1;
});
