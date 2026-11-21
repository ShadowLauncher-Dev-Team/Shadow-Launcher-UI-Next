// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#include "stdafx.h"
#include "AppWindow.h"

#include <shlwapi.h>
#include <shlobj.h>
#include <WebView2EnvironmentOptions.h>

using namespace Microsoft::WRL;

namespace {

constexpr wchar_t kClassName[] = L"ShadowWv2LoginWindow";
constexpr wchar_t kAuthUrl[] =
    L"https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize";
constexpr wchar_t kRedirectPrefix[] =
    L"https://login.microsoftonline.com/common/oauth2/nativeclient";
constexpr wchar_t kRedirectUriEncoded[] =
    L"https%3A%2F%2Flogin.microsoftonline.com%2Fcommon%2Foauth2%2Fnativeclient";

// ── 页面内「关闭」按钮的接管脚本 ──────────────────────────────────
// 背景：这类登录页（嵌入式布局）会画一个自己的关闭 X，点它执行 window.close()。
// 但 Chromium 规定「脚本只能关闭由脚本打开的窗口」，普通窗口上的 window.close()
// 会被静默忽略 —— 于是 WindowCloseRequested 根本不触发，宿主什么也收不到
// （上一版只订阅了那个事件，实测点了没反应）。
// 所以这里直接覆盖 window.close，把「想关闭」这个意图主动上报给宿主；
// 再用捕获阶段的点击监听兜底：有些不走 close() 的按钮靠 id/aria-label 识别。
// 发送的消息以 WV2CLOSE 开头，宿主收到就关窗。
constexpr wchar_t kCloseHookScript[] = LR"JS(
(function () {
  if (window.__shadowWv2Hooked) return;
  window.__shadowWv2Hooked = true;
  function post(m) { try { window.chrome.webview.postMessage(m); } catch (e) {} }
  try {
    window.close = function () { post('WV2CLOSE:js'); };
  } catch (e) {}
  document.addEventListener('click', function (ev) {
    try {
      var el = ev.target;
      var chain = [];
      var matched = false;
      for (var i = 0; i < 6 && el; i++, el = el.parentElement) {
        var tag = (el.tagName || '').toLowerCase();
        var id = el.id || '';
        var cls = (typeof el.className === 'string') ? el.className : '';
        var aria = (el.getAttribute && el.getAttribute('aria-label')) || '';
        var title = el.title || '';
        // 用子串判断而不是带 i 的正则：/i 会把 [^a-z] 也变成排除大写，
        // 于是 closeBtn 这类驼峰 id 匹配不上（实测踩过）。
        var blob = (id + ' ' + cls + ' ' + aria + ' ' + title).toLowerCase();
        if (blob.indexOf('close') >= 0 || blob.indexOf('dismiss') >= 0
            || blob.indexOf('cancel') >= 0 || blob.indexOf('关闭') >= 0) matched = true;
        chain.push(tag + '#' + id + '.' + cls.slice(0, 40) + '[' + aria + '][' + title + ']');
      }
      // 命中「关闭类」标识 → 直接请求关窗；否则只上报，留给日志排查
      post((matched ? 'WV2CLOSEBTN:' : 'WV2CLICKANY:') + chain.join(' < ').slice(0, 220));
    } catch (e) {}
  }, true);
})();
)JS";

} // namespace

std::string AppWindow::toUtf8(const std::wstring& w) {
    if (w.empty()) {
        return {};
    }
    const int len = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
    std::string out(static_cast<size_t>(len > 0 ? len - 1 : 0), '\0');
    if (len > 1) {
        WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, out.data(), len, nullptr, nullptr);
    }
    return out;
}

AppWindow::AppWindow(std::wstring clientId, std::wstring outputFile, std::wstring userDataFolder)
    : m_clientId(std::move(clientId)),
      m_outputFile(std::move(outputFile)),
      m_userDataFolder(std::move(userDataFolder)) {}

AppWindow::~AppWindow() {}

LRESULT CALLBACK AppWindow::WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    AppWindow* self = nullptr;
    if (msg == WM_NCCREATE) {
        auto* cs = reinterpret_cast<CREATESTRUCTW*>(lParam);
        self = reinterpret_cast<AppWindow*>(cs->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    } else {
        self = reinterpret_cast<AppWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    }

    if (self) {
        switch (msg) {
        case WM_SIZE:
            if (self->m_controller) {
                RECT r{};
                GetClientRect(hwnd, &r);
                self->m_controller->put_Bounds(r);
            }
            return 0;
        case WM_CLOSE:
            DestroyWindow(hwnd);
            return 0;
        case WM_DESTROY:
            // User closed the window without completing login → cancelled.
            self->Finish(1);
            PostQuitMessage(1);
            return 0;
        }
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

bool AppWindow::Initialize(HINSTANCE hInstance, int nCmdShow) {
    WNDCLASSEXW wc{sizeof(WNDCLASSEXW)};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = kClassName;
    if (!RegisterClassExW(&wc)) {
        return false;
    }

    m_window = CreateWindowExW(WS_EX_TOPMOST, kClassName, L"Microsoft 登录",
                               WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
                               CW_USEDEFAULT, CW_USEDEFAULT, 480, 650, nullptr, nullptr,
                               hInstance, this);
    if (!m_window) {
        return false;
    }
    ShowWindow(m_window, nCmdShow);
    UpdateWindow(m_window);

    // Ensure the user data folder exists before WebView2 tries to use it.
    if (!m_userDataFolder.empty()) {
        SHCreateDirectoryExW(nullptr, m_userDataFolder.c_str(), nullptr);
    }

    Log(L"window created");
    CreateWebView2();
    return true;
}

void AppWindow::CreateWebView2() {
    const HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(
        nullptr, m_userDataFolder.empty() ? nullptr : m_userDataFolder.c_str(), nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [this](HRESULT result, ICoreWebView2Environment* env) -> HRESULT {
                if (FAILED(result) || !env) {
                    MessageBoxW(m_window, L"WebView2 运行时不可用", L"登录", MB_OK);
                    Finish(2);
                    return S_OK;
                }
                m_environment = env; // AddRef — kept alive for async controller creation
                m_environment->CreateCoreWebView2Controller(
                    m_window,
                    Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                        [this](HRESULT res2, ICoreWebView2Controller* controller) -> HRESULT {
                            if (FAILED(res2) || !controller) {
                                MessageBoxW(m_window, L"WebView2 控制器创建失败", L"登录", MB_OK);
                                Finish(2);
                                return S_OK;
                            }
                            m_controller = controller;
                            controller->get_CoreWebView2(&m_webView);
                            Log(L"controller ready");

                            // ── 页面自己的「关闭」按钮 ────────────────────────────
                            // 两条路都接上，缺一不可（见 kCloseHookScript 上面的说明）：
                            //   ① WindowCloseRequested —— 正常会由 window.close() 触发；
                            //   ② 脚本注入 + WebMessageReceived —— close() 被 Chromium 拦掉时的兜底。
                            m_webView->add_WindowCloseRequested(
                                Callback<ICoreWebView2WindowCloseRequestedEventHandler>(
                                    [this](ICoreWebView2*, IUnknown*) -> HRESULT {
                                        Log(L"event: WindowCloseRequested");
                                        RequestClose();
                                        return S_OK;
                                    }).Get(),
                                &m_closeToken);

                            m_webView->AddScriptToExecuteOnDocumentCreated(kCloseHookScript, nullptr);
                            m_webView->add_WebMessageReceived(
                                Callback<ICoreWebView2WebMessageReceivedEventHandler>(
                                    [this](ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
                                        wil::unique_cotaskmem_string msg;
                                        if (SUCCEEDED(args->TryGetWebMessageAsString(&msg)) && msg) {
                                            const std::wstring s(msg.get());
                                            Log(L"webmessage: " + s.substr(0, 240));
                                            if (s.rfind(L"WV2CLOSE", 0) == 0) RequestClose();
                                        }
                                        return S_OK;
                                    }).Get(),
                                &m_msgToken);
                            RECT r{};
                            GetClientRect(m_window, &r);
                            m_controller->put_Bounds(r);

                            // Standard desktop Edge UA — WebView2's default UA
                            // ("Cortana ...") makes login.live.com serve a
                            // different responsive layout (extra close button).
                            wil::com_ptr<ICoreWebView2Settings> settings;
                            if (SUCCEEDED(m_webView->get_Settings(&settings))) {
                                wil::com_ptr<ICoreWebView2Settings2> settings2;
                                if (SUCCEEDED(settings->QueryInterface(IID_PPV_ARGS(&settings2)))) {
                                    settings2->put_UserAgent(
                                        L"Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                                        L"AppleWebKit/537.36 (KHTML, like Gecko) "
                                        L"Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0");
                                }
                            }

                            // Intercept the nativeclient redirect and capture the code.
                            m_webView->add_NavigationStarting(
                                Callback<ICoreWebView2NavigationStartingEventHandler>(
                                    [this](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
                                        wil::unique_cotaskmem_string uri;
                                        if (SUCCEEDED(args->get_Uri(&uri)) && uri) {
                                            const std::wstring url(uri.get());
                                            if (url.rfind(kRedirectPrefix, 0) == 0) {
                                                args->put_Cancel(TRUE);
                                                const size_t pos = url.find(L"code=");
                                                if (pos != std::wstring::npos) {
                                                    std::wstring code = url.substr(pos + 5);
                                                    const size_t amp = code.find(L'&');
                                                    if (amp != std::wstring::npos) {
                                                        code = code.substr(0, amp);
                                                    }
                                                    Finish(0, code);
                                                }
                                            }
                                        }
                                        return S_OK;
                                    }).Get(),
                                &m_navToken);

                            std::wstring url = kAuthUrl;
                            url += L"?client_id=" + m_clientId;
                            url += L"&response_type=code";
                            url += L"&redirect_uri=" + std::wstring(kRedirectUriEncoded);
                            url += L"&scope=XboxLive.signin%20offline_access";
                            url += L"&prompt=select_account";
                            m_webView->Navigate(url.c_str());
                            return S_OK;
                        }).Get());
                return S_OK;
            }).Get());

    if (FAILED(hr)) {
        MessageBoxW(m_window, L"WebView2 环境创建失败", L"登录", MB_OK);
        Finish(2);
    }
}

void AppWindow::RequestClose() {
    if (!m_window || m_closingForGood) return;
    m_closingForGood = true;
    Log(L"request close -> WM_CLOSE");
    PostMessageW(m_window, WM_CLOSE, 0, 0);
}

void AppWindow::Log(const std::wstring& line) {
    if (m_outputFile.empty()) return;
    const std::wstring path = m_outputFile + L".dbg.log";
    HANDLE h = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                           OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return;
    SYSTEMTIME st{};
    GetLocalTime(&st);
    wchar_t stamp[32]{};
    swprintf_s(stamp, L"%02d:%02d:%02d ", st.wHour, st.wMinute, st.wSecond);
    const std::string utf8 = toUtf8(std::wstring(stamp) + line + L"\r\n");
    DWORD written = 0;
    WriteFile(h, utf8.data(), static_cast<DWORD>(utf8.size()), &written, nullptr);
    CloseHandle(h);
}

void AppWindow::Finish(int exitCode, const std::wstring& code) {
    if (m_finished) {
        return;
    }
    m_finished = true;

    if (!m_outputFile.empty()) {
        // Write UTF-8 (code is ASCII; UTF-8 keeps the reader side simple).
        std::string utf8;
        if (code.empty()) {
            utf8 = "cancel";
        } else {
            utf8 = "code=" + toUtf8(code);
        }
        HANDLE hFile = CreateFileW(m_outputFile.c_str(), GENERIC_WRITE, 0, nullptr,
                                   CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (hFile != INVALID_HANDLE_VALUE) {
            DWORD written = 0;
            WriteFile(hFile, utf8.data(), static_cast<DWORD>(utf8.size()), &written, nullptr);
            CloseHandle(hFile);
        }
    }
    PostQuitMessage(exitCode);
}
