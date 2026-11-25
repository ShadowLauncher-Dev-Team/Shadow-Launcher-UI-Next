#include "java_backend.h"
#include "core/file_downloader.h"
#include "core/java_runtime_installer.h"
#include "utils/logger.h"
#include <QNetworkReply>
#include <QRegularExpression>
#include <QDir>
#include <QFileInfo>
#include <QJsonObject>
#include <QJsonArray>
#include <QCoreApplication>

using namespace ShadowDownloader;

namespace ShadowLauncher {

JavaBackend::JavaBackend(QObject *parent)
    : QObject(parent)
    , m_baseUrl("https://mirrors.tuna.tsinghua.edu.cn/Adoptium")
    , m_nam(new QNetworkAccessManager(this))
    , m_runtimeInstaller(new JavaRuntimeInstaller(this))
{
    qCInfo(logJava) << QStringLiteral("Java后端初始化");
    // 不再在构造时就去请求 Adoptium 目录：启动时没人看这张列表，
    // 推迟到用户真的打开「下载 → Java」时（QML 调 ensureVersionsLoaded）。
    // 见 design/startup-perf-audit-2026-11-20.md 条目 C。

    // ── 转发一键安装信号 ──
    connect(m_runtimeInstaller, &JavaRuntimeInstaller::javaInstalled,
            this, &JavaBackend::javaInstalled);
    connect(m_runtimeInstaller, &JavaRuntimeInstaller::finished,
            this, &JavaBackend::javaInstallFinished);
    connect(m_runtimeInstaller, &JavaRuntimeInstaller::progressChanged,
            this, &JavaBackend::javaInstallStateChanged);
    connect(m_runtimeInstaller, &JavaRuntimeInstaller::runningChanged,
            this, &JavaBackend::javaInstallStateChanged);
    connect(m_runtimeInstaller, &JavaRuntimeInstaller::logMessage,
            this, &JavaBackend::logMessage);
    connect(m_runtimeInstaller, &JavaRuntimeInstaller::systemJavaScanFinished,
            this, &JavaBackend::systemJavaScanFinished);
    connect(m_runtimeInstaller, &JavaRuntimeInstaller::downloadProgressChanged,
            this, &JavaBackend::javaDownloadProgressChanged);
    // 每装完一个就刷新 java_cache 列表（页面上的"已装"状态）
    connect(m_runtimeInstaller, &JavaRuntimeInstaller::javaInstalled,
            this, [this](const QString&, const QString&, bool) { emit javaCacheListChanged(); });
    connect(m_runtimeInstaller, &JavaRuntimeInstaller::finished,
            this, [this](bool, const QString&) {
                m_installingMajor.clear();
                emit javaInstallStateChanged();
                emit javaCacheListChanged();
            });
}

// ── Setters trigger cascading fetches ──

void JavaBackend::setSelectedVersion(const QString &v) {
    if (m_selVersion == v) return;
    m_selVersion = v;
    setSelectedType("");  // cascades → setSelectedArch("") → setSelectedOS("")
    m_types.clear();
    emit selectedVersionChanged();
    emit javaTypesChanged();
    if (!v.isEmpty()) fetchTypes();
}

void JavaBackend::setSelectedType(const QString &t) {
    if (m_selType == t) return;
    m_selType = t;
    setSelectedArch("");  // cascades → setSelectedOS("")
    m_archs.clear();
    emit selectedTypeChanged();
    emit javaArchsChanged();
    if (!t.isEmpty()) fetchArchs();
}

void JavaBackend::setSelectedArch(const QString &a) {
    if (m_selArch == a) return;
    m_selArch = a;
    setSelectedOS("");
    m_oses.clear();
    emit selectedArchChanged();
    emit javaOSesChanged();
    if (!a.isEmpty()) fetchOSes();
}

void JavaBackend::setSelectedOS(const QString &o) {
    if (m_selOS == o) return;
    m_selOS = o;
    m_files.clear();
    emit selectedOSChanged();
    emit javaFilesChanged();
    if (!o.isEmpty()) fetchFiles();
}

// ── Fetch methods ──

// 按需加载：首次进入 Java 页才请求一次；已有列表或在途请求时直接返回（可重复调用）。
void JavaBackend::ensureVersionsLoaded()
{
    if (!m_versions.isEmpty() || m_versionsFetching) return;
    m_versionsFetching = true;
    refreshVersions();
}

void JavaBackend::refreshVersions() {
    qCInfo(logJava) << QStringLiteral("刷新Java版本列表");
    fetchUrl(m_baseUrl + "/", [this](const QStringList &dirs) {
        m_versionsFetching = false;
        m_versions.clear();
        for (const auto &d : dirs) {
            // Only numeric version directories
            bool ok;
            d.toInt(&ok);
            if (ok) m_versions.append(d);
        }
        std::sort(m_versions.begin(), m_versions.end(), [](const QString &a, const QString &b) {
            return a.toInt() > b.toInt();
        });
        qCInfo(logJava) << QStringLiteral("版本列表刷新完成 共%1个").arg(m_versions.size());
        emit javaVersionsChanged();
    }, [this](int code, const QString &err) {
        // 失败要复位：否则 ensureVersionsLoaded 会一直以为「请求在途」，用户下次进页面也不会重试
        m_versionsFetching = false;
        qCWarning(logJava) << QStringLiteral("版本列表刷新失败 code=%1 %2").arg(code).arg(err);
    });
}

void JavaBackend::fetchTypes() {
    QString url = m_baseUrl + "/" + m_selVersion + "/";
    qCInfo(logJava) << QStringLiteral("获取Java类型 version=%1").arg(m_selVersion);
    fetchUrl(url, [this](const QStringList &dirs) {
        m_types = dirs;
        qCInfo(logJava) << QStringLiteral("Java类型获取完成 count=%1").arg(m_types.size());
        emit javaTypesChanged();
    });
}

void JavaBackend::fetchArchs() {
    QString url = m_baseUrl + "/" + m_selVersion + "/" + m_selType + "/";
    qCInfo(logJava) << QStringLiteral("获取Java架构 version=%1 type=%2").arg(m_selVersion, m_selType);
    fetchUrl(url, [this](const QStringList &dirs) {
        m_archs = dirs;
        qCInfo(logJava) << QStringLiteral("Java架构获取完成 count=%1").arg(m_archs.size());
        emit javaArchsChanged();
    });
}

void JavaBackend::fetchOSes() {
    QString url = m_baseUrl + "/" + m_selVersion + "/" + m_selType + "/" + m_selArch + "/";
    qCInfo(logJava) << QStringLiteral("获取Java操作系统 version=%1").arg(m_selVersion);
    fetchUrl(url, [this](const QStringList &dirs) {
        m_oses = dirs;
        qCInfo(logJava) << QStringLiteral("Java操作系统获取完成 count=%1").arg(m_oses.size());
        emit javaOSesChanged();
    });
}

void JavaBackend::fetchFiles() {
    QString url = m_baseUrl + "/" + m_selVersion + "/" + m_selType + "/" + m_selArch + "/" + m_selOS + "/";
    qCInfo(logJava) << QStringLiteral("获取Java安装包 version=%1").arg(m_selVersion);
    fetchFileList(url, [this](const QVariantList &files) {
        m_files = files;
        qCInfo(logJava) << QStringLiteral("Java安装包获取完成 count=%1").arg(m_files.size());
        emit javaFilesChanged();
    });
}

// ── URL fetching + parsing ──

void JavaBackend::fetchUrl(const QString &url,
                           std::function<void(const QStringList &)> callback,
                           std::function<void(int, const QString &)> onError)
{
    m_fetching = true;
    emit fetchingChanged();

    qCInfo(logJava) << QStringLiteral("HTTP GET url=%1").arg(url);

    QUrl qurl(url);
    QNetworkRequest req(qurl);
    req.setRawHeader("User-Agent", "ShadowLauncher/1.0");
    QNetworkReply *reply = m_nam->get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, callback, onError, url]() {
        reply->deleteLater();
        m_fetching = false;
        emit fetchingChanged();

        if (reply->error() != QNetworkReply::NoError) {
            qCWarning(logJava) << QStringLiteral("GET失败 url=%1 错误=%2").arg(url, reply->errorString());
            emit logMessage(QString("获取列表失败: %1").arg(reply->errorString()));
            if (onError) onError(reply->error(), reply->errorString());
            return;
        }

        QByteArray data = reply->readAll();
        QStringList items = parseDirListing(data, false);
        qCInfo(logJava) << QStringLiteral("GET成功 url=%1").arg(url);
        callback(items);
    });
}

void JavaBackend::fetchFileList(const QString &url,
                                std::function<void(const QVariantList &)> callback)
{
    m_fetching = true;
    emit fetchingChanged();

    QUrl qurl(url);
    QNetworkRequest req(qurl);
    req.setRawHeader("User-Agent", "ShadowLauncher/1.0");
    QNetworkReply *reply = m_nam->get(req);

    QString capturedUrl = url;  // copy for lambda
    connect(reply, &QNetworkReply::finished, this, [this, reply, callback, capturedUrl]() {
        reply->deleteLater();
        m_fetching = false;
        emit fetchingChanged();

        if (reply->error() != QNetworkReply::NoError) {
            emit logMessage(QString("获取文件列表失败: %1").arg(reply->errorString()));
            return;
        }

        QByteArray data = reply->readAll();

        // Parse only <td class="link"> entries with size info
        static QRegularExpression re(
            R"(<td class="link">\s*<a\s+href=\"([^\"]+)\"[^>]*>([^<]+)</a>\s*</td>\s*<td[^>]*>([^<]+)</td>)",
            QRegularExpression::CaseInsensitiveOption
        );

        QVariantList files;
        auto it = re.globalMatch(QString::fromUtf8(data));
        while (it.hasNext()) {
            auto m = it.next();
            QString href = m.captured(1);
            QString name = m.captured(2);
            QString sizeStr = m.captured(3).trimmed();

            // Skip directories (href ends with /)
            if (href.endsWith("/")) continue;
            // Skip parent directory
            if (href == "../") continue;

            if (name.isEmpty()) name = href;

            // Parse size
            qint64 size = 0;
            if (!sizeStr.isEmpty() && sizeStr != "-") {
                // Could be "141.1 MB" or "5242880" format
                static QRegularExpression sizeRe(R"(([\d.]+)\s*([KMGT]?B?))");
                auto sm = sizeRe.match(sizeStr);
                if (sm.hasMatch()) {
                    double val = sm.captured(1).toDouble();
                    QString unit = sm.captured(2).toUpper();
                    if (unit == "KB" || unit == "K") val *= 1024;
                    else if (unit == "MB" || unit == "M") val *= 1024 * 1024;
                    else if (unit == "GB" || unit == "G") val *= 1024 * 1024 * 1024;
                    else if (unit == "TB" || unit == "T") val *= 1024LL * 1024 * 1024 * 1024;
                    size = (qint64)val;
                } else {
                    size = sizeStr.toLongLong();
                }
            }

            // Only include .msi and .zip (and .tar.gz)
            QString lower = name.toLower();
            if (!lower.endsWith(".msi") && !lower.endsWith(".zip") && !lower.endsWith(".tar.gz"))
                continue;

            QJsonObject obj;
            obj["name"] = name;
            obj["url"] = capturedUrl + name;
            obj["size"] = size;
            obj["ext"] = lower.endsWith(".msi") ? "msi" : (lower.endsWith(".tar.gz") ? "tar.gz" : "zip");
            files.append(obj.toVariantMap());
        }

        emit logMessage(QString("找到 %1 个安装包").arg(files.size()));
        callback(files);
    });
}

QStringList JavaBackend::parseDirListing(const QByteArray &html, bool filesOnly)
{
    QStringList items;

    // Match <td class="link"><a href="name/"> entries (avoids footer links)
    static QRegularExpression re(
        R"(<td class="link">\s*<a\s+href=\"([^\"]+)\"[^>]*>([^<]*)</a>\s*</td>)",
        QRegularExpression::CaseInsensitiveOption
    );

    auto it = re.globalMatch(QString::fromUtf8(html));
    while (it.hasNext()) {
        auto m = it.next();
        QString href = m.captured(1);
        QString text = m.captured(2);

        // Skip parent dir
        if (href == "../" || href == "/") continue;

        // Get clean name
        QString name = text.isEmpty() ? href : text;
        name.replace("/", "");

        if (filesOnly) {
            // Only files, not dirs
            if (href.endsWith("/")) continue;
            items.append(name);
        } else {
            // Only dirs, not files
            if (!href.endsWith("/")) continue;
            items.append(name);
        }
    }

    items.removeDuplicates();
    return items;
}

// ── Download ──

QString JavaBackend::fileDownloadUrl(const QString &filename) const
{
    return m_baseUrl + "/" + m_selVersion + "/" + m_selType + "/"
           + m_selArch + "/" + m_selOS + "/" + filename;
}

QString JavaBackend::javaInstallDir() const
{
    // 必须与另外两条通路（JavaRuntimeInstaller / ModLoaderInstaller）以及
    // scanSystemJavas 的扫描根保持一致：exe 所在目录，而不是进程工作目录。
    // 用 currentPath 时，从快捷方式/别的程序拉起（CWD != exeDir）会把 Java 存到
    // 一个启动器永远不会扫描的目录 → 表现为"下载好了但没有 Java"。
    return QCoreApplication::applicationDirPath() + "/java_cache";
}

void JavaBackend::downloadJavaFileTo(const QString &filename, const QString &outDir, qint64 expectedSize)
{
    QString url = fileDownloadUrl(filename);
    QString outPath = outDir + "/" + filename;
    qCInfo(logJava) << QStringLiteral("开始下载Java url=%1 目标=%2").arg(url, outPath);

    // Recreate downloader each time so totalBytes resets to 0
    if (m_downloader) {
        m_downloader->deleteLater();
        m_downloader = nullptr;
    }

    m_downloader = new FileDownloader(this);
    m_downloader->setMaxThreads(1);  // 单线程下载，根本解决多线程 Range 分裂文件损坏问题

    connect(m_downloader, &FileDownloader::progressChanged, this,
            [this](int, int, qint64 dl, qint64 total) {
                double speed = m_downloader->currentSpeedMBps();
                // 进度计数可能短暂超过总量，cap 到 100 防止进度条爆掉
                int pct = total > 0 ? qMin(100, (int)(dl * 100 / total)) : 0;
                emit downloadProgress(pct, dl, total, speed);
            });

    connect(m_downloader, &FileDownloader::fileFinished, this,
        [this](const QString &path, bool ok) {
            emit downloadFinished(ok, path);
        });

    connect(m_downloader, &FileDownloader::logMessage, this,
        [this](const QString &msg) {
            emit logMessage(msg);
        });

    QDir().mkpath(outDir);
    QFile::remove(outPath);

    m_downloader->addFile(outPath, filename, {url}, expectedSize, QByteArray());
    m_downloader->start();

    emit logMessage(QString("开始下载: %1").arg(filename));
}

void JavaBackend::downloadJavaFile(const QString &filename)
{
    downloadJavaFileTo(filename, javaInstallDir(), 0);
}

void JavaBackend::cancelDownload()
{
    qCInfo(logJava) << QStringLiteral("取消Java下载");
    if (m_downloader) {
        // 先 cancel 再 deleteLater：cancel 会 abort 在途请求并停止写盘，只 deleteLater 可能留下半个文件
        m_downloader->cancel();
        m_downloader->deleteLater();
        m_downloader = nullptr;
    }
}

// ── 下载页 Java Tab ──

QString JavaBackend::installStatusText() const
{
    return m_runtimeInstaller ? m_runtimeInstaller->statusText() : QString();
}

void JavaBackend::installJavaRuntime(int major, const QString& type, const QString& arch)
{
    if (major <= 0) { emit logMessage(QStringLiteral("无效的 Java 主版本")); return; }
    if (m_runtimeInstaller->running()) {
        emit logMessage(QStringLiteral("已有 Java 任务在进行中，请稍候"));
        return;
    }
    m_installingMajor = QString::number(major);
    emit javaInstallStateChanged();
    qCInfo(logJava) << QStringLiteral("Java页安装 major=%1 type=%2 arch=%3")
                           .arg(major).arg(type, arch);
    m_runtimeInstaller->installJavaAsync(major, type,
        [this](bool ok, const QString& err, const QString& exe) {
            m_installingMajor.clear();
            emit javaInstallStateChanged();
            emit javaCacheListChanged();
            // 审计修复：成功时第二参数原本塞的是 java.exe 路径（这个参数在 QML 里叫 error，
            // 一旦有页面把它当错误文案显示，"安装成功"会变成一段路径文字）
            emit javaInstallFinished(ok, ok ? QString() : err);
        },
        arch);
}

void JavaBackend::downloadJavaFileToPath(const QString& url, const QString& savePath, qint64 expectedSize)
{
    if (url.isEmpty() || savePath.isEmpty()) return;
    if (m_downloader) {
        m_downloader->cancel();
        m_downloader->deleteLater();
        m_downloader = nullptr;
    }
    m_downloader = new FileDownloader(this);
    m_downloader->setMaxThreads(1);
    connect(m_downloader, &FileDownloader::progressChanged, this,
            [this](int, int, qint64 dl, qint64 total) {
                const int pct = total > 0 ? qMin(100, static_cast<int>(dl * 100 / total)) : 0;
                emit downloadProgress(pct, dl, total, m_downloader->currentSpeedMBps());
            });
    connect(m_downloader, &FileDownloader::fileFinished, this,
            [this](const QString& path, bool ok) { emit downloadFinished(ok, path); });
    connect(m_downloader, &FileDownloader::logMessage, this,
            [this](const QString& msg) { emit logMessage(msg); });

    qCInfo(logJava) << QStringLiteral("Java页保存文件 url=%1 目标=%2").arg(url, savePath);
    m_downloader->addFile(savePath, QFileInfo(savePath).fileName(), {url}, expectedSize, QByteArray());
    m_downloader->start();
}

QVariantList JavaBackend::javaCacheRuntimes() const
{
    QVariantList out;
    const QString root = QCoreApplication::applicationDirPath() + QStringLiteral("/java_cache");
    QDir dir(root);
    if (!dir.exists()) return out;
    for (const QString& sub : dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        bool ok = false;
        const int major = sub.toInt(&ok);
        if (!ok) continue;
        const QString exe = root + QStringLiteral("/") + sub + QStringLiteral("/bin/java.exe");
        if (!QFile::exists(exe)) continue;
        QVariantMap m;
        m[QStringLiteral("major")] = major;
        m[QStringLiteral("path")] = exe;
        m[QStringLiteral("isJdk")] = QFile::exists(root + QStringLiteral("/") + sub + QStringLiteral("/bin/javac.exe"));
        m[QStringLiteral("version")] = JavaRuntimeInstaller::verifyJavaMajor(exe) > 0
            ? QString::number(JavaRuntimeInstaller::verifyJavaMajor(exe)) : QString();
        m[QStringLiteral("complete")] = JavaRuntimeInstaller::isJavaComplete(exe);
        out.append(m);
    }
    return out;
}

// ============================================================
// 一键安装所需 Java（转发 JavaRuntimeInstaller）
// ============================================================

void JavaBackend::installRequiredJavas()
{
    m_runtimeInstaller->installRequiredJavas();
}

void JavaBackend::cancelJavaInstall()
{
    m_runtimeInstaller->cancelInstall();
}

void JavaBackend::installJavaForLaunch(int majorVersion,
                                       std::function<void(int, const QString&)> onProgress,
                                       std::function<void(bool, const QString&, const QString&)> onDone)
{
    // ── 用 JDK 而不是 JRE ──
    // JRE 裁剪了 jdk.crypto.ec 等模块，NeoForge 1.21.8+ 启动时报
    // "Module jdk.crypto.ec not found" 崩溃。JDK 包含全部模块。
    // 进度：JavaRuntimeInstaller 的 downloadProgressChanged 信号 → onProgress 回调
    auto* conn = new QMetaObject::Connection;
    *conn = connect(m_runtimeInstaller, &JavaRuntimeInstaller::downloadProgressChanged,
                    this, [this, onProgress]() {
                        if (onProgress)
                            onProgress(m_runtimeInstaller->downloadPercent(),
                                       m_runtimeInstaller->statusText());
                    });
    m_runtimeInstaller->installJavaAsync(majorVersion, QStringLiteral("jdk"),
        [this, conn, onDone](bool ok, const QString& err, const QString& exe) {
            disconnect(*conn);
            delete conn;
            if (onDone) onDone(ok, err, exe);
        });
}

QVariantList JavaBackend::scanSystemJavas()
{
    return m_runtimeInstaller->scanSystemJavas();
}

QVariantList JavaBackend::detectedSystemJavas() const
{
    return m_runtimeInstaller->detectedSystemJavas();
}

QString JavaBackend::cpuArch() const
{
    return m_runtimeInstaller->cpuArch();
}

bool JavaBackend::javaInstalling() const
{
    return m_runtimeInstaller->running();
}

int JavaBackend::javaInstallStep() const
{
    return m_runtimeInstaller->currentStep();
}

int JavaBackend::javaInstallTotal() const
{
    return m_runtimeInstaller->totalSteps();
}

QString JavaBackend::javaInstallStatus() const
{
    return m_runtimeInstaller->statusText();
}

int JavaBackend::javaDownloadPercent() const
{
    return m_runtimeInstaller->downloadPercent();
}

qint64 JavaBackend::javaDownloadBytes() const
{
    return m_runtimeInstaller->downloadBytes();
}

qint64 JavaBackend::javaDownloadTotal() const
{
    return m_runtimeInstaller->downloadTotal();
}

double JavaBackend::javaDownloadSpeedMBps() const
{
    return m_runtimeInstaller->downloadSpeedMBps();
}

} // namespace ShadowLauncher
