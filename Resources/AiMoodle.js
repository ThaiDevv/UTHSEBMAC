/*
 * AI Moodle UTHSEB - License-based Version v4.0
 * Compatible with WebView2 (Windows) and WebKit / WKWebView (macOS)
 *
 * This version requires a valid license key from the AI Moodle backend.
 * API calls are routed through the backend server instead of direct Gemini API access.
 *
 * License activation: POST /api/v1/license/activate
 * License validation: POST /api/v1/license/validate
 * AI Proxy: POST /api/v1/chat/completions
 */

(function () {
    'use strict';

    // Only run in top-level window (prevent running in child iframes)
    if (typeof window !== 'undefined' && window.top !== window) {
        return;
    }

    // ── Bridge Detection ──────────────────────────────────────────────
    const IS_WEBVIEW2 = typeof window.chrome !== 'undefined' &&
        typeof window.chrome.webview !== 'undefined';
    const IS_WEBKIT = typeof window.webkit !== 'undefined' &&
        typeof window.webkit.messageHandlers !== 'undefined' &&
        typeof window.webkit.messageHandlers.uthseb !== 'undefined';

    function postMessageToHost(message) {
        if (IS_WEBVIEW2) {
            try {
                window.chrome.webview.postMessage(message);
            } catch (e) {
                console.warn('[AI Moodle] WebView2 postMessage failed:', e);
            }
        } else if (IS_WEBKIT) {
            try {
                window.webkit.messageHandlers.uthseb.postMessage(message);
            } catch (e) {
                console.warn('[AI Moodle] WebKit postMessage failed:', e);
            }
        }
    }

    function addMessageListener(callback) {
        if (IS_WEBVIEW2) {
            window.chrome.webview.addEventListener('message', function (event) {
                callback(event.data);
            });
        }
        window.addEventListener('message', function (event) {
            callback(event.data);
        });
    }

    // ── Safe Storage Helper (WebKit / about:blank compatibility) ───────
    const SafeStorage = {
        getItem: function (key) {
            try {
                if (typeof localStorage !== 'undefined') {
                    return localStorage.getItem(key);
                }
            } catch (e) {}
            return null;
        },
        setItem: function (key, value) {
            try {
                if (typeof localStorage !== 'undefined') {
                    localStorage.setItem(key, value);
                }
            } catch (e) {}
        },
        removeItem: function (key) {
            try {
                if (typeof localStorage !== 'undefined') {
                    localStorage.removeItem(key);
                }
            } catch (e) {}
        }
    };

    // ── Configuration ────────────────────────────────────────────────
    const CONFIG = {
        API_BASE_URL: SafeStorage.getItem('aimoodle_api_url') || 'http://13.211.200.63:3000',
        LICENSE_KEY: 'sebuth_mac_license_token',
        DEVICE_ID_KEY: 'aimoodle_device_id',
        STORAGE_PREFIX: 'aimoodle_',

        // Product identifier for license validation
        PRODUCT_SLUG: 'sebuthmac',

        // Request settings
        MAX_RETRIES: 3,
        REQUEST_TIMEOUT: 30000,

        // Subject for AI (can be customized)
        SUBJECT: 'Information Technology'
    };

    // ── State ──────────────────────────────────────────────────────
    let currentToken = null;
    let deviceId = null;
    let isInitialized = false;
    let pendingPasteCallback = null;

    // ── Message Handler ──────────────────────────────────────────────
    addMessageListener(function (message) {
        if (!message || typeof message !== 'object') return;

        if (message.type === 'pasteData') {
            if (pendingPasteCallback && message.text !== undefined) {
                pendingPasteCallback(message.text);
                pendingPasteCallback = null;
            }
        }
    });

    // ── Device ID Management ─────────────────────────────────────────
    function getOrCreateDeviceId() {
        let id = SafeStorage.getItem(CONFIG.DEVICE_ID_KEY);
        if (!id) {
            id = 'seb_' + Date.now() + '_' + Math.random().toString(36).substring(2, 15);
            SafeStorage.setItem(CONFIG.DEVICE_ID_KEY, id);
        }
        return id;
    }

    // ── Native Bridge for WebKit (CORS & Mixed-Content bypass) ───────
    function nativeApiCall(endpoint, options) {
        return new Promise(function (resolve, reject) {
            const reqId = 'req_' + Date.now() + '_' + Math.random().toString(36).substring(2, 9);
            window.__pendingNativeApiRequests = window.__pendingNativeApiRequests || {};
            window.__pendingNativeApiRequests[reqId] = { resolve: resolve, reject: reject };

            postMessageToHost({
                type: 'apiCall',
                id: reqId,
                endpoint: endpoint,
                method: options.method || 'GET',
                headers: options.headers || {},
                body: options.body || null
            });

            setTimeout(function () {
                if (window.__pendingNativeApiRequests && window.__pendingNativeApiRequests[reqId]) {
                    delete window.__pendingNativeApiRequests[reqId];
                    reject(new Error('Yêu cầu mạng hết thời gian chờ'));
                }
            }, CONFIG.REQUEST_TIMEOUT || 30000);
        });
    }

    window.__handleNativeApiResponse = function (reqId, error, statusCode, responseText) {
        if (!window.__pendingNativeApiRequests || !window.__pendingNativeApiRequests[reqId]) return;
        const entry = window.__pendingNativeApiRequests[reqId];
        delete window.__pendingNativeApiRequests[reqId];

        if (error) {
            entry.reject(new Error(error));
            return;
        }

        try {
            const data = JSON.parse(responseText);
            if (statusCode >= 200 && statusCode < 300) {
                entry.resolve(data);
            } else {
                entry.reject(new Error(data.error || data.message || ('Lỗi kết nối (' + statusCode + ')')));
            }
        } catch (e) {
            entry.reject(new Error('Dữ liệu máy chủ không hợp lệ'));
        }
    };

    // ── API Functions ────────────────────────────────────────────────
    async function apiCall(endpoint, options = {}) {
        const defaultHeaders = {
            'Content-Type': 'application/json',
            'X-Product-Slug': CONFIG.PRODUCT_SLUG
        };

        if (currentToken) {
            defaultHeaders['Authorization'] = 'Bearer ' + currentToken;
        }

        const mergedHeaders = {
            ...defaultHeaders,
            ...options.headers
        };

        // Trên WebKit (macOS), route qua Native URLSession bridge để vượt rào cản Mixed Content và CORS
        if (IS_WEBKIT) {
            return await nativeApiCall(endpoint, {
                ...options,
                headers: mergedHeaders
            });
        }

        // Trên WebView2 / môi trường thông thường
        const url = CONFIG.API_BASE_URL + endpoint;
        const response = await fetch(url, {
            ...options,
            headers: mergedHeaders
        });

        const data = await response.json();

        if (!response.ok) {
            throw new Error(data.error || data.message || 'API request failed');
        }

        return data;
    }

    // ── License Activation ──────────────────────────────────────────────
    async function activateLicense(licenseKey) {
        try {
            const response = await apiCall('/api/v1/license/activate', {
                method: 'POST',
                body: JSON.stringify({
                    licenseKey: licenseKey,
                    deviceId: deviceId,
                    productSlug: CONFIG.PRODUCT_SLUG
                })
            });

            if (response.success && response.token) {
                SafeStorage.setItem(CONFIG.LICENSE_KEY, response.token);
                SafeStorage.setItem(CONFIG.LICENSE_KEY + '_info', JSON.stringify({
                    plan: response.plan,
                    expiresAt: response.expiresAt,
                    activatedAt: Date.now()
                }));

                currentToken = response.token;

                // Sync token to host
                postMessageToHost({
                    type: 'licenseTokenSync',
                    token: response.token
                });

                return {
                    success: true,
                    plan: response.plan,
                    token: response.token
                };
            }

            return {
                success: false,
                reason: response.error || response.message || response.reason || 'Kích hoạt license thất bại'
            };
        } catch (error) {
            console.error('[AI Moodle] License activation error:', error);
            return {
                success: false,
                reason: error.message || 'Không thể kết nối đến server'
            };
        }
    }

    async function validateLicense() {
        let storedToken = SafeStorage.getItem(CONFIG.LICENSE_KEY);
        if (!storedToken && window.__syncedLicenseToken) {
            storedToken = window.__syncedLicenseToken;
        }

        if (!storedToken) {
            return { valid: false, reason: 'no_token' };
        }

        try {
            const data = await apiCall('/api/v1/license/validate', {
                method: 'POST',
                body: JSON.stringify({ productSlug: CONFIG.PRODUCT_SLUG })
            });

            if (data.success && data.valid) {
                currentToken = storedToken;
                SafeStorage.setItem(CONFIG.LICENSE_KEY, storedToken);
                return { valid: true, plan: data.plan, expiresAt: data.expiresAt };
            } else {
                SafeStorage.removeItem(CONFIG.LICENSE_KEY);
                currentToken = null;
                postMessageToHost({ type: 'licenseRevoked' });
                return { valid: false, reason: data.reason || 'invalid' };
            }
        } catch (error) {
            console.warn('[AI Moodle] License validation error:', error.message);
            SafeStorage.removeItem(CONFIG.LICENSE_KEY);
            currentToken = null;
            postMessageToHost({ type: 'licenseRevoked' });
            return { valid: false, reason: 'License không hợp lệ hoặc đã hết hạn.' };
        }
    }

    // ── Clipboard Paste Handler ────────────────────────────────────────
    async function requestClipboardText() {
        return new Promise(function (resolve) {
            if (IS_WEBVIEW2 || IS_WEBKIT) {
                pendingPasteCallback = resolve;
                postMessageToHost({ type: 'clipboardRequest' });

                setTimeout(function () {
                    if (pendingPasteCallback === resolve) {
                        pendingPasteCallback = null;
                        resolve('');
                    }
                }, 3000);
            } else {
                resolve('');
            }
        });
    }

    // ── AI Chat Completion ───────────────────────────────────────────
    async function callAI(requestBody) {
        if (!currentToken) {
            throw new Error('Vui lòng nhập License Key để sử dụng');
        }

        let lastError = null;

        for (let attempt = 0; attempt < CONFIG.MAX_RETRIES; attempt++) {
            try {
                const response = await apiCall('/api/v1/chat/completions', {
                    method: 'POST',
                    body: JSON.stringify(requestBody)
                });

                if (response.success) {
                    if (response.text) {
                        return response.text;
                    }

                    if (response.response?.candidates?.[0]?.content?.parts?.[0]?.text) {
                        return response.response.candidates[0].content.parts[0].text.trim();
                    }

                    if (response.choices?.[0]?.message?.content) {
                        return response.choices[0].message.content.trim();
                    }
                }

                throw new Error(response.error || 'Không có phản hồi từ AI');
            } catch (error) {
                lastError = error;
                console.warn(`[AI Moodle] Attempt ${attempt + 1} failed:`, error.message);

                const errorMsg = error.message.toLowerCase();
                if (errorMsg.includes('license') || errorMsg.includes('quyền') ||
                    errorMsg.includes('hết hạn') || errorMsg.includes('unauthorized') ||
                    errorMsg.includes('401') || errorMsg.includes('403')) {
                    throw error;
                }

                if (attempt < CONFIG.MAX_RETRIES - 1) {
                    await new Promise(function (r) { setTimeout(r, 1000 * (attempt + 1)); });
                }
            }
        }

        throw lastError || new Error('Yêu cầu AI thất bại sau nhiều lần thử');
    }

    // ── License Modal UI ─────────────────────────────────────────────
    function createLicenseModal(onSuccess, initialMessage) {
        if (initialMessage === undefined) initialMessage = '';

        const existingModal = document.getElementById('aimoodle-license-modal');
        if (existingModal) existingModal.remove();

        const modal = document.createElement('div');
        modal.id = 'aimoodle-license-modal';
        modal.style.cssText =
            'position: fixed; top: 0; left: 0; width: 100%; height: 100%; ' +
            'background: rgba(0, 0, 0, 0.75); display: flex; align-items: center; ' +
            'justify-content: center; z-index: 999999; ' +
            'font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;';

        modal.innerHTML = '<div style="' +
            'background: #f5f5f5; border-radius: 16px; padding: 32px; ' +
            'max-width: 400px; width: 90%; box-shadow: 0 20px 60px rgba(0,0,0,0.4); ' +
            'text-align: center; animation: aimoodleFadeIn 0.25s ease-out;">' +
            '<style>' +
            '@keyframes aimoodleFadeIn {' +
            '  from { opacity: 0; transform: scale(0.95) translateY(15px); }' +
            '  to { opacity: 1; transform: scale(1) translateY(0); }' +
            '}</style>' +

            '<div style="margin-bottom: 24px;">' +
            '<div style="' +
            '  width: 60px; height: 60px; ' +
            '  background: linear-gradient(135deg, #1a5f7a 0%, #0d3b4f 100%); ' +
            '  border-radius: 14px; margin: 0 auto 16px; ' +
            '  display: flex; align-items: center; justify-content: center; ' +
            '  box-shadow: 0 4px 12px rgba(0,0,0,0.2);">' +
            '<svg width="28" height="28" fill="#87ceeb" viewBox="0 0 24 24">' +
            '<path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm0 10.99h7c-.53 4.12-3.28 7.79-7 8.94V12H5V6.3l7-3.11v8.8z"/>' +
            '</svg></div>' +
            '<h2 style="margin: 0 0 8px; color: #444; font-size: 22px; font-weight: 600;">UTH SEB</h2>' +
            '<p style="margin: 0; color: #888; font-size: 14px;">Nhập License Key để kích hoạt</p></div>' +

            '<div id="aimoodle-license-message" style="' +
            '  display: ' + (initialMessage ? 'block' : 'none') + ';' +
            '  padding: 10px 14px; background: #fff8e1; border: 1px solid #ffe082; ' +
            '  border-radius: 8px; color: #f57c00; font-size: 13px; margin-bottom: 16px;">' +
            initialMessage + '</div>' +

            '<div style="margin-bottom: 16px; display: flex; gap: 8px;">' +
            '<input type="text" id="aimoodle-license-input" placeholder="Nhập hoặc nhấn Ctrl+V/Cmd+V để dán..." style="' +
            '  flex: 1; padding: 14px 16px; border: 1px solid #ccc; border-radius: 10px; ' +
            '  font-size: 13px; font-family: Consolas, Monaco, Courier New, monospace; ' +
            '  box-sizing: border-box; transition: all 0.2s; letter-spacing: 0.5px; ' +
            '  background: #fff; color: #444;"/>' +
            '<button type="button" id="aimoodle-license-paste" title="Dán mã từ bộ nhớ tạm" style="' +
            '  padding: 0 16px; background: #eee; border: 1px solid #ccc; ' +
            '  border-radius: 10px; color: #444; font-size: 13px; font-weight: 500; ' +
            '  cursor: pointer; display: flex; align-items: center; gap: 4px; ' +
            '  white-space: nowrap; transition: all 0.2s;">' +
            '&#128203; Dán</button></div>' +

            '<button id="aimoodle-license-submit" style="' +
            '  width: 100%; padding: 14px; ' +
            '  background: linear-gradient(135deg, #1a5f7a 0%, #0d3b4f 100%); ' +
            '  border: none; border-radius: 10px; color: white; font-size: 15px; ' +
            '  font-weight: 500; cursor: pointer; transition: all 0.2s; ' +
            '  box-shadow: 0 3px 10px rgba(0,0,0,0.2);">' +
            'Kích hoạt License</button>' +

            '<p style="margin-top: 20px; color: #aaa; font-size: 11px; line-height: 1.5;">' +
            'License được lưu trên thiết bị<br>Liên hệ hỗ trợ nếu cần</p></div>';

        const input = modal.querySelector('#aimoodle-license-input');
        const pasteBtn = modal.querySelector('#aimoodle-license-paste');
        const submitBtn = modal.querySelector('#aimoodle-license-submit');
        const messageDiv = modal.querySelector('#aimoodle-license-message');

        // Paste button handler
        if (pasteBtn) {
            pasteBtn.addEventListener('click', async function (e) {
                e.preventDefault();
                e.stopPropagation();
                const clipText = await requestClipboardText();
                if (clipText && clipText.trim()) {
                    input.value = clipText.trim();
                }
                input.focus();
            });
        }

        // Intercept paste events specifically for the license input
        input.addEventListener('paste', function (e) {
            e.stopPropagation();
            if (e.clipboardData) {
                var text = e.clipboardData.getData('text');
                if (text) {
                    e.preventDefault();
                    var start = input.selectionStart || 0;
                    var end = input.selectionEnd || 0;
                    var val = input.value;
                    input.value = val.substring(0, start) + text.trim() + val.substring(end);
                    input.selectionStart = input.selectionEnd = start + text.trim().length;
                }
            }
        });

        input.addEventListener('keydown', function (e) {
            if ((e.ctrlKey || e.metaKey) && (e.key === 'v' || e.key === 'V')) {
                e.stopPropagation();
            }
        });

        function mountModal() {
            if (document.body) {
                if (!document.getElementById('aimoodle-license-modal')) {
                    document.body.appendChild(modal);
                }
                setTimeout(function () { if (input) input.focus(); }, 100);
                return;
            }
            var checkTimer = setInterval(function () {
                if (document.body) {
                    clearInterval(checkTimer);
                    if (!document.getElementById('aimoodle-license-modal')) {
                        document.body.appendChild(modal);
                    }
                    setTimeout(function () { if (input) input.focus(); }, 100);
                }
            }, 50);
        }

        mountModal();

        var handleSubmit = async function () {
            var licenseKey = input.value.trim();
            if (!licenseKey) {
                messageDiv.textContent = 'Vui lòng nhập License Key';
                messageDiv.style.display = 'block';
                messageDiv.style.background = '#ffebee';
                messageDiv.style.borderColor = '#ffcdd2';
                messageDiv.style.color = '#c62828';
                return;
            }

            submitBtn.disabled = true;
            submitBtn.innerHTML = '<span style="opacity:0.7">&#8987; Đang kích hoạt...</span>';
            submitBtn.style.opacity = '0.7';
            messageDiv.style.display = 'none';

            var result = await activateLicense(licenseKey);

            if (result.success) {
                window.__isSessionValidated = true;
                postMessageToHost({ type: 'sessionValidated' });
                postMessageToHost({ type: 'licenseTokenSync', token: result.token });
                messageDiv.textContent = '✓ Kích hoạt thành công! Gói: ' + (result.plan ? result.plan.toUpperCase() : '');
                messageDiv.style.display = 'block';
                messageDiv.style.background = '#e8f5e9';
                messageDiv.style.borderColor = '#a5d6a7';
                messageDiv.style.color = '#2e7d32';

                submitBtn.textContent = '✓ Thành công';

                setTimeout(function () {
                    modal.remove();
                    if (onSuccess) onSuccess();
                }, 1000);
            } else {
                messageDiv.textContent = '✗ ' + (result.reason || 'License không hợp lệ');
                messageDiv.style.display = 'block';
                messageDiv.style.background = '#ffebee';
                messageDiv.style.borderColor = '#ffcdd2';
                messageDiv.style.color = '#c62828';

                submitBtn.disabled = false;
                submitBtn.textContent = 'Kích hoạt License';
                submitBtn.style.opacity = '1';
            }
        };

        submitBtn.addEventListener('click', handleSubmit);
        input.addEventListener('keypress', function (e) {
            if (e.key === 'Enter') handleSubmit();
        });

        modal.addEventListener('click', function (e) {
            if (e.target === modal) {
                e.stopPropagation();
            }
        });
    }

    // ── Image Processing ─────────────────────────────────────────────
    async function processImage(imgEl) {
        try {
            var src = imgEl.src;
            if (src.toLowerCase().indexOf('.svg') !== -1 ||
                imgEl.classList.contains('questionflagimage') ||
                imgEl.classList.contains('activityicon') ||
                src.indexOf('/core/') !== -1 ||
                (imgEl.width > 0 && imgEl.width < 50)) return null;
            var blob = await (await fetch(src)).blob();
            return new Promise(function (res) {
                var reader = new FileReader();
                reader.onloadend = function () { res(reader.result.split(',')[1]); };
                reader.onerror = function () { res(null); };
                reader.readAsDataURL(blob);
            });
        } catch (e) { return null; }
    }

    async function processImagesWithMarker(container, prefix, startIdx) {
        if (!container) return { text: '', count: 0, markers: [] };
        var imgs = container.querySelectorAll('img');
        var text = '', count = 0;
        var markers = [];
        for (var i = 0; i < imgs.length; i++) {
            var b64 = await processImage(imgs[i]);
            if (b64) {
                count++;
                var marker = '[IMAGE_' + prefix + '_' + (startIdx + count) + ']';
                text += ' ' + marker + ' ';
                markers.push({ marker: marker, data: b64 });
            }
        }
        return { text: text, count: count, markers: markers };
    }

    // ── Question Processing ───────────────────────────────────────────
    async function extractQuestionData(qDiv) {
        var qTxt = '', promptTask = '';
        var imageMarkers = [];
        var formulation = qDiv.querySelector('.formulation');
        var inlineInputs = formulation ? formulation.querySelectorAll('input[type="text"]') : [];

        if (inlineInputs.length > 0) {
            var clone = formulation.cloneNode(true);
            var hiddenEls = clone.querySelectorAll('.accesshide');
            for (var h = 0; h < hiddenEls.length; h++) hiddenEls[h].remove();
            var textInputs = clone.querySelectorAll('input[type="text"]');
            for (var idx = 0; idx < textInputs.length; idx++) {
                var span = document.createElement('span');
                span.innerText = ' [BLANK_' + (idx + 1) + '] ';
                textInputs[idx].replaceWith(span);
            }
            qTxt = clone.innerText.trim();
            var r = await processImagesWithMarker(formulation, 'Q', 0);
            if (r.count > 0) { qTxt += '\n(Images: ' + r.text.trim() + ')'; imageMarkers = imageMarkers.concat(r.markers); }
            promptTask = 'Task: Fill in [BLANK_x]. Return just the word/phrase. Format: "1. answer"';
        } else {
            var qTextEl = qDiv.querySelector('.qtext');
            qTxt = qTextEl ? qTextEl.innerText.trim() : '';
            var qr = await processImagesWithMarker(qTextEl, 'Q', 0);
            if (qr.count > 0) { qTxt += '\n(Images: ' + qr.text.trim() + ')'; imageMarkers = imageMarkers.concat(qr.markers); }

            var ansEl = qDiv.querySelector('.answer');
            var ansTxt = '';
            if (ansEl) {
                var selects = ansEl.querySelectorAll('select');
                if (selects.length > 0) {
                    promptTask = 'Task: Match items in "Left Column" with the correct option in "Right Column". Return pairs clearly. Example 1-{answer}\n2-{answer}\n...';
                    ansTxt += '\n--- Left Column ---\n';
                    var rows = ansEl.querySelectorAll('tr');
                    for (var ri = 0; ri < rows.length; ri++) {
                        var tc = rows[ri].querySelector('.text');
                        if (tc) ansTxt += 'Item ' + (ri + 1) + ': ' + tc.innerText.trim() + '\n';
                    }
                    ansTxt += '\n--- Right Column ---\n';
                    var opts = selects[0].options;
                    var optTexts = [];
                    for (var oi = 0; oi < opts.length; oi++) {
                        var optText = opts[oi].innerText.trim();
                        if (!/^(Choose|Chọn)(\.\.\.)?$/i.test(optText) && optText !== '') {
                            optTexts.push(optText);
                        }
                    }
                    ansTxt += optTexts.join('\n');
                } else {
                    promptTask = 'Task: Choose the correct option. Return ONLY the answer text.';
                    var ansImgIdx = 0;
                    var optEls = ansEl.querySelectorAll('.r0, .r1, label');
                    for (var oe = 0; oe < optEls.length; oe++) {
                        var optTxt = optEls[oe].innerText.replace(/\n+/g, ' ').trim();
                        var imgMarks = '';
                        var optImgs = optEls[oe].querySelectorAll('img');
                        for (var pi = 0; pi < optImgs.length; pi++) {
                            var b64 = await processImage(optImgs[pi]);
                            if (b64) {
                                ansImgIdx++;
                                var m = '[IMAGE_A_' + ansImgIdx + ']';
                                imgMarks += ' ' + m;
                                imageMarkers.push({ marker: m, data: b64 });
                            }
                        }
                        ansTxt += imgMarks ? (optTxt + imgMarks + '\n') : (optTxt + '\n');
                    }
                }
            }
            qTxt += '\n' + ansTxt;
        }
        return { qTxt: qTxt, promptTask: promptTask, imageMarkers: imageMarkers };
    }

    function buildPrompt(qTxt, promptTask, imageMarkers) {
        var imageNote = '';
        if (imageMarkers.length > 0)
            imageNote = '\n\nNote: Images are provided in order as marked. IMAGE_Q_x = Question images, IMAGE_A_x = Answer option images.';
        return 'Role: Expert in ' + CONFIG.SUBJECT + '.\n' + promptTask + '\n\nQuestion Context:\n' + qTxt + imageNote + '\n\nConstraint: Short, direct answer.';
    }

    function buildRequestBody(prompt, imageMarkers) {
        var parts = [{ text: prompt }];
        for (var i = 0; i < imageMarkers.length; i++) {
            parts.push({ inline_data: { mime_type: 'image/png', data: imageMarkers[i].data } });
        }
        return { contents: [{ parts: parts }] };
    }

    // ── Question UI ───────────────────────────────────────────────────
    function createQuestionUI(qDiv) {
        if (qDiv.querySelector('.gemini-trigger')) return;
        qDiv.style.position = 'relative';

        var btn = document.createElement('div');
        btn.className = 'gemini-trigger';
        btn.style.cssText =
            'position: absolute; bottom: 0; right: 0; width: 36px; height: 36px; ' +
            'cursor: pointer; z-index: 9999; background: transparent; border: none; ' +
            'outline: none; opacity: 0;';

        var resBox = document.createElement('div');
        resBox.className = 'gemini-result-box';
        resBox.style.cssText =
            'position: absolute; bottom: 6px; right: 40px; max-width: 480px; ' +
            'width: max-content; max-height: 140px; overflow-y: auto; font-size: 11px; ' +
            'line-height: 1.3; padding: 2px 6px; background: transparent; border: none; ' +
            'border-radius: 4px; z-index: 10000; cursor: pointer; display: none; ' +
            'color: #444; opacity: 0.2; transition: opacity 0.2s ease; user-select: none;';
        resBox.onmouseover = function () { this.style.opacity = '0.75'; };
        resBox.onmouseout = function () { this.style.opacity = '0.2'; };
        resBox.onclick = function () { this.style.display = 'none'; };

        btn.onclick = async function () {
            if (!currentToken) {
                createLicenseModal(function () {
                    processQuestion();
                });
                return;
            }
            processQuestion();
        };

        async function processQuestion() {
            resBox.style.display = 'block';
            resBox.innerHTML = '<span style="opacity: 0.3;">...</span>';

            try {
                var data = await extractQuestionData(qDiv);
                var prompt = buildPrompt(data.qTxt, data.promptTask, data.imageMarkers);
                var requestBody = buildRequestBody(prompt, data.imageMarkers);

                var result = await callAI(requestBody);

                // Loại bỏ toàn bộ icon, emoji, tiền tố "Đáp án:" để hiển thị tàng hình
                var cleanAnswer = (result || '')
                    .replace(/[\u{1F300}-\u{1F9FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]/gu, '')
                    .replace(/^(đáp án|câu trả lời|answer)\s*[:：\-]\s*/i, '')
                    .replace(/\*\*(.*?)\*\*/g, '$1')
                    .trim();

                resBox.innerHTML = cleanAnswer.replace(/\n/g, '<br>');
            } catch (err) {
                if (err.message.includes('License') ||
                    err.message.includes('license') ||
                    err.message.includes('unauthorized') ||
                    err.message.includes('401') ||
                    err.message.includes('403')) {
                    resBox.innerHTML = '<span style="opacity: 0.4;">License hết hạn hoặc không hợp lệ</span>';
                    SafeStorage.removeItem(CONFIG.LICENSE_KEY);
                    currentToken = null;
                    postMessageToHost({ type: 'licenseRevoked' });
                    setTimeout(function () { createLicenseModal(null, 'License hết hạn hoặc không hợp lệ'); }, 1000);
                } else {
                    resBox.innerHTML = '<span style="opacity: 0.4;">' + err.message + '</span>';
                }
                console.error('[AI Moodle]', err);
            }
        }

        qDiv.appendChild(btn);
        qDiv.appendChild(resBox);
    }

    // ── Initialization ───────────────────────────────────────────────
    async function init() {
        deviceId = getOrCreateDeviceId();

        // 1. Kiểm tra token đã lưu trên máy
        var storedToken = SafeStorage.getItem(CONFIG.LICENSE_KEY);
        if (!storedToken && window.__syncedLicenseToken) {
            storedToken = window.__syncedLicenseToken;
            SafeStorage.setItem(CONFIG.LICENSE_KEY, storedToken);
        }

        // 2. Chưa có key nào trên máy -> Hiện popup yêu cầu kích hoạt
        if (!storedToken) {
            createLicenseModal(null, 'Vui lòng nhập License Key để sử dụng.');
            return;
        }

        currentToken = storedToken;

        // 3. Trong khi app đang chạy (phiên đã được xác thực trước đó) -> KHÔNG CHECK LẠI NỮA
        if (window.__isSessionValidated) {
            setupQuestionUI();
            return;
        }

        // 4. Khi mới vào app lần đầu trong phiên -> Kiểm tra xem key còn hoạt động không
        try {
            var validation = await validateLicense();
            if (!validation || !validation.valid) {
                // Key đã hết hạn hoặc không đúng cho product này
                SafeStorage.removeItem(CONFIG.LICENSE_KEY);
                currentToken = null;
                postMessageToHost({ type: 'licenseRevoked' });
                var message = (validation && validation.reason === 'expired')
                    ? 'License đã hết hạn. Vui lòng nhập license mới.'
                    : 'License không hợp lệ hoặc đã bị khóa. Vui lòng nhập license mới.';
                if (!document.getElementById('aimoodle-license-modal')) {
                    createLicenseModal(null, message);
                }
            } else {
                // Key hợp lệ -> Đánh dấu phiên này đã được duyệt
                window.__isSessionValidated = true;
                postMessageToHost({ type: 'sessionValidated' });
                setupQuestionUI();
            }
        } catch (err) {
            console.error('[AI Moodle] Init validation error:', err);
            SafeStorage.removeItem(CONFIG.LICENSE_KEY);
            currentToken = null;
            postMessageToHost({ type: 'licenseRevoked' });
            if (!document.getElementById('aimoodle-license-modal')) {
                createLicenseModal(null, 'Vui lòng nhập License Key để kích hoạt.');
            }
        }
    }

    function setupQuestionUI() {
        var questions = document.querySelectorAll('.que');
        for (var i = 0; i < questions.length; i++) {
            createQuestionUI(questions[i]);
        }
    }

    function bootstrap() {
        var start = async function () {
            if (!isInitialized) {
                isInitialized = true;
                await init();
            }
        };

        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', start);
        } else {
            start();
        }

        var checkInterval = setInterval(function () {
            if (document.body) {
                clearInterval(checkInterval);
                start();
            }
        }, 100);

        setInterval(function () {
            var questions = document.querySelectorAll('.que:not(.gemini-trigger)');
            for (var i = 0; i < questions.length; i++) {
                createQuestionUI(questions[i]);
            }
        }, 2000);
    }

    bootstrap();
    console.log('[AI Moodle UTHSEB] Loaded successfully (Cross-platform WebView2 / WebKit)');
})();
