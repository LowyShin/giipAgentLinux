#!/usr/bin/env node
/**
 * scenario-test-runner.js
 * 시나리오 테스트 Playwright 실행기
 * giip-878: 시나리오 테스트 기능
 *
 * 사용법:
 *   node scenario-test-runner.js --stSn=1 --strSn=1 --ak=<token>
 *
 * 환경변수 (보안):
 *   SCENARIO_TEST_PW_<USERNAME> - 테스트 계정 비밀번호
 *   또는 giipAgent.cnf에 SCENARIO_TEST_PW_<USERNAME>=<pw>로 설정
 */

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const https = require('https');
const http = require('http');

// === 설정 ===
const API_BASE = process.env.GIIP_API_ADDR || 'https://giipfaw.azurewebsites.net/api/giipApiSk2';
const RESULT_DIR = process.env.SCENARIO_TEST_RESULT_DIR || '/tmp/scenario-test-results';

// === 유틸리티 ===

/** HTTP 요청 (giipApiSk2 포맷) */
function apiRequest(command, jsondata = {}) {
    return new Promise((resolve, reject) => {
        const postData = JSON.stringify({ text: command, jsondata });
        const url = new URL(API_BASE);
        const options = {
            hostname: url.hostname,
            path: url.pathname,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(postData)
            }
        };

        const req = https.request(options, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try { resolve(JSON.parse(data)); }
                catch (e) { reject(new Error(`JSON parse failed: ${data}`)); }
            });
        });
        req.on('error', reject);
        req.write(postData);
        req.end();
    });
}

/** 타임스탬프 */
function timestamp() {
    return new Date().toISOString();
}

/** 결과 저장 디렉토리 생성 */
function ensureResultDir(runId) {
    const dir = path.join(RESULT_DIR, `run_${runId}`);
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
    }
    return dir;
}

/** 스텝 결과 기록 */
function log(msg) {
    console.log(`[${timestamp()}] ${msg}`);
}

// === 메인 ===

async function main() {
    const args = process.argv.slice(2).reduce((acc, arg) => {
        const [k, v] = arg.split('=');
        acc[k.replace(/^--/, '')] = v;
        return acc;
    }, {});

    const stSn = parseInt(args.stSn, 10);
    const strSn = parseInt(args.strSn, 10);
    const ak = args.ak;

    if (!stSn || !strSn || !ak) {
        console.error('사용법: node scenario-test-runner.js --stSn=<id> --strSn=<runId> --ak=<token>');
        process.exit(1);
    }

    log(`시나리오 테스트 실행 시작: stSn=${stSn}, strSn=${strSn}`);

    // 1. 시나리오 정보 조회
    let scenario;
    try {
        const resp = await apiRequest('ScenarioTestList stSn limit', { stSn, limit: 1 }, ak);
        const rows = parseApiResponse(resp);
        if (!rows || rows.length === 0) throw new Error(`시나리오 ${stSn}를 찾을 수 없습니다.`);
        scenario = rows[0];
        log(`시나리오 로드 완료: ${scenario.stName}`);
    } catch (e) {
        await updateRunStatus(strSn, ak, 'error', { error: e.message });
        throw e;
    }

    // 2. 실행 상태 → running
    await updateRunStatus(strSn, ak, 'running');
    const startTime = Date.now();
    const resultDir = ensureResultDir(strSn);
    const screenshots = [];
    const errors = [];
    const stepResults = [];

    let browser;
    let context;
    let page;

    try {
        // 3. Playwright 브라우저 시작
        log('Playwright 브라우저 시작 (headless Chromium)');
        browser = await chromium.launch({
            headless: true,
            args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
        });
        context = await browser.newContext({
            viewport: { width: 1280, height: 720 },
            ignoreHTTPSErrors: true
        });
        page = await context.newPage();

        // 콘솔 에러 수집
        page.on('console', msg => {
            if (msg.type() === 'error') {
                errors.push({ type: 'console_error', text: msg.text(), timestamp: timestamp() });
            }
        });
        page.on('pageerror', err => {
            errors.push({ type: 'page_error', text: err.message, timestamp: timestamp() });
        });
        page.on('requestfailed', req => {
            errors.push({ type: 'request_failed', url: req.url(), failure: req.failure()?.errorText, timestamp: timestamp() });
        });

        // 4. 스텝 실행
        const steps = JSON.parse(scenario.stepsJson || '[]');
        log(`총 ${steps.length}개 스텝 실행`);

        for (let i = 0; i < steps.length; i++) {
            const step = steps[i];
            const stepStart = Date.now();
            let stepResult = { stepIndex: i, action: step.action, status: 'passed' };

            try {
                log(`스텝 ${i + 1}/${steps.length}: ${step.action}`);

                switch (step.action) {
                    case 'login': {
                        // 대상 URL로 먼저 이동
                        if (scenario.targetUrl) {
                            await page.goto(scenario.targetUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
                        }
                        // 로그인 폼 입력
                        if (step.username) {
                            const userField = step.usernameSelector || 'input[name="userid"], input[name="username"], input[type="text"]';
                            await page.waitForSelector(userField, { timeout: 10000 }).catch(() => {});
                            await page.fill(userField, step.username);
                        }
                        if (step.password) {
                            const pwField = step.passwordSelector || 'input[name="password"], input[type="password"]';
                            await page.fill(pwField, step.password);
                        }
                        const submitSel = step.submitSelector || 'button[type="submit"], input[type="submit"]';
                        await page.click(submitSel);
                        await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
                        break;
                    }

                    case 'navigate': {
                        await page.goto(step.url, { waitUntil: 'domcontentloaded', timeout: 30000 });
                        break;
                    }

                    case 'click': {
                        await page.waitForSelector(step.selector, { timeout: step.timeout || 10000 });
                        await page.click(step.selector);
                        if (step.waitForNav) {
                            await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
                        }
                        break;
                    }

                    case 'input': {
                        await page.waitForSelector(step.selector, { timeout: step.timeout || 10000 });
                        await page.fill(step.selector, step.value || '');
                        break;
                    }

                    case 'wait': {
                        await page.waitForSelector(step.selector, { timeout: step.timeout || 10000 });
                        break;
                    }

                    case 'assert': {
                        const el = await page.$(step.selector);
                        if (!el) {
                            throw new Error(`Selector not found: ${step.selector}`);
                        }

                        if (step.condition === 'visible') {
                            const visible = await el.isVisible();
                            if (String(visible) !== String(step.expected)) {
                                throw new Error(`Assertion failed: visible=${visible}, expected=${step.expected}`);
                            }
                        } else if (step.condition === 'text') {
                            const text = await el.textContent();
                            if (!step.expected || !text.includes(step.expected)) {
                                throw new Error(`Assertion failed: text="${text}", expected contains="${step.expected}"`);
                            }
                        } else if (step.condition === 'url') {
                            const url = page.url();
                            if (!url.includes(step.expected)) {
                                throw new Error(`Assertion failed: url="${url}", expected contains="${step.expected}"`);
                            }
                        }
                        break;
                    }

                    case 'screenshot': {
                        const name = step.name || `step_${i}`;
                        const screenshotPath = path.join(resultDir, `${name}.png`);
                        await page.screenshot({ path: screenshotPath, fullPage: step.fullPage || false });
                        screenshots.push({ name, path: screenshotPath });
                        log(`스크린샷 저장: ${screenshotPath}`);
                        break;
                    }

                    default:
                        log(`알 수 없는 액션: ${step.action}`);
                }

                stepResult.durationMs = Date.now() - stepStart;
                stepResults.push(stepResult);

            } catch (err) {
                stepResult.status = 'failed';
                stepResult.error = err.message;
                stepResult.durationMs = Date.now() - stepStart;
                stepResults.push(stepResult);
                errors.push({ type: 'step_error', stepIndex: i, action: step.action, error: err.message, timestamp: timestamp() });
                log(`스텝 ${i + 1} 실패: ${err.message}`);
                // 첫 번째 실패에서 중지 (후속 스텝은 의미 없음)
                break;
            }
        }

        // 5. 최종 결과 판단
        const allPassed = stepResults.every(r => r.status === 'passed');
        const finalStatus = allPassed ? 'passed' : 'failed';
        const durationMs = Date.now() - startTime;

        // 6. 결과 저장
        const resultJson = JSON.stringify({
            steps: stepResults,
            screenshots,
            errors,
            finalStatus
        });

        await saveRunResult(strSn, ak, finalStatus, resultJson, resultDir, durationMs);
        log(`실행 완료: status=${finalStatus}, duration=${durationMs}ms, passed=${stepResults.filter(r => r.status === 'passed').length}/${stepResults.length}`);

    } catch (err) {
        log(`실행 중 치명적 오류: ${err.message}`);
        await updateRunStatus(strSn, ak, 'error', JSON.stringify({ fatalError: err.message, errors }));
    } finally {
        if (browser) await browser.close().catch(() => {});
    }
}

// === API 응답 파싱 ===

function parseApiResponse(resp) {
    if (!resp) return [];
    if (Array.isArray(resp)) {
        // [[rows], {RstVal}] 형태
        if (Array.isArray(resp[0])) return resp[0];
        return resp;
    }
    return [];
}

// === 결과 저장 ===

async function updateRunStatus(strSn, ak, status, resultJson = null) {
    try {
        // finishedAt, resultJson 업데이트는 별도 SP가 필요하지만,
        // 여기서는 resultJson만 KVS에 임시 저장
        if (resultJson) {
            await apiRequest('KVSWrite', {
                key: `scenario-test-result:${strSn}`,
                value: resultJson,
                keyType: 'strSn',
                csn: 0  // CSN은 runner가 알 수 없음, API에서 처리
            }, ak);
        }
        log(`실행 상태 업데이트: ${status}`);
    } catch (e) {
        log(`상태 업데이트 실패 (무시): ${e.message}`);
    }
}

async function saveRunResult(strSn, ak, status, resultJson, screenshotDir, durationMs) {
    try {
        await apiRequest('ScenarioTestRunSave', {
            strSn,
            runStatus: status,
            resultJson,
            screenshotDir,
            durationMs
        }, ak);
    } catch (e) {
        log(`결과 저장 실패: ${e.message}`);
    }
}

// 실행
main().catch(err => {
    console.error(`[FATAL] ${err.message}`);
    process.exit(1);
});
