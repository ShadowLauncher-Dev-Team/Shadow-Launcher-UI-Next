// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#include "logger.h"

#ifdef Q_OS_WIN
#include <windows.h>
#endif

#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMutexLocker>
#include <QMutex>
#include <QRegularExpression>
#include <QSysInfo>
#include <QTextStream>
#include <QtMessageHandler>
#include <cstdio>

namespace ShadowLauncher {

// ── Module categories (short, readable names) ──
Q_LOGGING_CATEGORY(logApp,      "Shadow.App")
Q_LOGGING_CATEGORY(logAccount,  "Shadow.Account")
Q_LOGGING_CATEGORY(logVersion,  "Shadow.Version")
Q_LOGGING_CATEGORY(logLaunch,   "Shadow.Launch")
Q_LOGGING_CATEGORY(logDownload, "Shadow.Download")
Q_LOGGING_CATEGORY(logMod,      "Shadow.Mod")       // 模组/光影/资源包管理
Q_LOGGING_CATEGORY(logLoader,   "Shadow.Loader")    // Forge/Fabric/NeoForge 安装
Q_LOGGING_CATEGORY(logJava,     "Shadow.Java")      // Java 运行时检测
Q_LOGGING_CATEGORY(logNet,      "Shadow.Net")       // 联机网络
Q_LOGGING_CATEGORY(logUI,       "Shadow.UI")        // 用户界面操作
// Keep legacy 'logMgr' for backward compat — maps to same "Shadow.Mod"
Q_LOGGING_CATEGORY(logMgr,      "Shadow.Mod")

// ============================================================
// 日志落盘策略（2026-11-15 重做）
//
// 旧做法：一天一个文件、只追加。结果是一天的开发会写进同一份文件，
// 实测单日 82 MB / 69.5 万行，而其中 92% 是三类循环回声（安装器 JVM 逐行、
// 游戏 JVM 逐行、同一条 QML 绑定环告警刷 12.5 万次）。
// 现在：
//   1. **一次启动一个文件**：logs/shadow_launcher_<yyyy-MM-dd_HH-mm-ss>.log
//      —— 出问题时「哪一次运行」天然可指认，不会和别的会话混在一起。
//   2. **只留最近 10 份**：启动时按修改时间清掉更早的（含旧的按日文件）。
//   3. **连续重复折叠**：同一条消息连续出现 N 次只落 1 行 + 一句折叠计数。
//      这是兜底：即使某处又把循环日志写回来，也不会再把磁盘写爆。
//   4. **单次上限 12 MB**：超了写一句提示后停止写文件（控制台照旧）。
//   5. 文件头带版本 / PID / 系统 / 路径，拿到日志就能对上环境。
// ============================================================

static QRecursiveMutex g_logMutex;
static QFile* g_logFile = nullptr;
static QString g_logDir;
static QString g_sessionStamp;      // 本次运行的时间戳（文件名用）
static QDateTime g_sessionStart;
static qint64 g_bytesWritten = 0;
static bool g_sizeLimitHit = false;
static int g_repeatCount = 0;       // 上一条消息连续出现了几次
static QString g_repeatKey;         // 上一条消息的折叠键

static constexpr int    kKeepLogFiles   = 10;
static constexpr qint64 kMaxSessionBytes = 12LL * 1024 * 1024;

static QString logDirPath(const QString& exeDir)
{
    return exeDir + QStringLiteral("/logs");
}

static QString logFilePath(const QString& exeDir)
{
    // 没有会话时间戳时退回按日（尚未初始化就写日志的极端情况）
    if (g_sessionStamp.isEmpty())
        return logDirPath(exeDir) + QStringLiteral("/shadow_launcher_")
               + QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd"))
               + QStringLiteral(".log");
    return logDirPath(exeDir) + QStringLiteral("/shadow_launcher_") + g_sessionStamp
           + QStringLiteral(".log");
}

static void ensureLogDir(const QString& exeDir)
{
    QDir dir(logDirPath(exeDir));
    if (!dir.exists())
        dir.mkpath(QStringLiteral("."));
}

// 只留最近 kKeepLogFiles 份。只动我们自己的文件名模式，绝不碰目录里别的东西。
static void pruneOldLogs(const QString& exeDir)
{
    QDir dir(logDirPath(exeDir));
    if (!dir.exists())
        return;

    // 旧方案（一天一个文件）的遗留：shadow_launcher_2026-11-14.log
    // 与新方案 shadow_launcher_2026-11-14_20-31-05.log 的区别就是日期后面没有 _时间。
    // 一次性清掉——它们既不符合保留策略，也是当初把磁盘写爆的那批文件（实测单份 84 MB）。
    static const QRegularExpression legacyRx(
        QStringLiteral("^shadow_launcher_[0-9]{4}-[0-9]{2}-[0-9]{2}\\.log$"));
    const QFileInfoList legacy = dir.entryInfoList(
        { QStringLiteral("shadow_launcher_*.log") }, QDir::Files);
    for (const QFileInfo& fi : legacy) {
        if (legacyRx.match(fi.fileName()).hasMatch())
            dir.remove(fi.fileName());
    }
    const QFileInfoList files = dir.entryInfoList(
        { QStringLiteral("shadow_launcher_*.log") },
        QDir::Files, QDir::Time);          // Time = 新→旧
    for (int i = kKeepLogFiles; i < files.size(); ++i) {
        if (!dir.remove(files.at(i).fileName()))
            fprintf(stderr, "[Logger] 旧日志删除失败: %s\n",
                    qPrintable(files.at(i).absoluteFilePath()));
    }
}

static void writeRaw(const QString& text)
{
    if (!g_logFile || !g_logFile->isOpen())
        return;
    if (g_bytesWritten >= kMaxSessionBytes) {
        if (!g_sizeLimitHit) {
            g_sizeLimitHit = true;
            const QString note = QStringLiteral(
                "… 本次会话日志已达 %1 MB 上限，后续内容不再写入文件（控制台仍然输出）")
                .arg(kMaxSessionBytes / (1024 * 1024));
            QTextStream s(g_logFile);
            s.setEncoding(QStringConverter::Utf8);
            s << note << Qt::endl;
            s.flush();
            g_bytesWritten += note.size();
        }
        return;
    }
    QTextStream stream(g_logFile);
    stream.setEncoding(QStringConverter::Utf8);
    stream << text << Qt::endl;
    stream.flush();
    g_bytesWritten += text.toUtf8().size() + 1;
}

// 连续重复的收束点：离开上一段重复时补一句“重复 N 次”
static void flushRepeatMarker()
{
    if (g_repeatCount > 1) {
        const QString marker = QStringLiteral("… 上一条连续重复 %1 次（已折叠，未逐行落盘）")
                                   .arg(g_repeatCount - 1);
        writeRaw(QStringLiteral("        ") + marker);
    }
    g_repeatCount = 0;
    g_repeatKey.clear();
}

// 文件头：拿到一份日志就知道是哪次运行、什么环境
static void writeSessionHeader(const QString& exeDir)
{
    const QString version = QCoreApplication::applicationVersion().isEmpty()
                                ? QStringLiteral("unknown")
                                : QCoreApplication::applicationVersion();
    writeRaw(QStringLiteral("——  Shadow Launcher  ——"));
    writeRaw(QStringLiteral("会话 %1   PID %2")
                 .arg(g_sessionStamp)
                 .arg(QCoreApplication::applicationPid()));
    writeRaw(QStringLiteral("版本 %1   系统 %2   Qt %3")
                 .arg(version,
                      QSysInfo::prettyProductName(),
                      QString::fromLatin1(qVersion())));
    writeRaw(QStringLiteral("目录 %1").arg(exeDir));
    writeRaw(QStringLiteral("────────────────────────────"));
}

static void openSessionLog(const QString& exeDir)
{
    if (g_logFile) {
        if (g_logFile->isOpen()) g_logFile->close();
        delete g_logFile;
        g_logFile = nullptr;
    }

    ensureLogDir(exeDir);

    g_logFile = new QFile(logFilePath(exeDir));
    if (!g_logFile->open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
        delete g_logFile;
        g_logFile = nullptr;
        return;
    }
    g_bytesWritten = 0;
    g_sizeLimitHit = false;
    writeSessionHeader(exeDir);

    // 清理放在**新建之后**：本次文件是最新的，按时间保留最新 10 份即可，
    // 先清后建会变成“清到 10 份再新建”= 11 份。
    pruneOldLogs(exeDir);
}

static void shadowMessageHandler(QtMsgType type,
                                  const QMessageLogContext& ctx,
                                  const QString& msg)
{
    // ── Production: skip debug messages entirely ──
    // QML console.log() is QtDebugMsg — not written by default.
    // QML console.info() is QtInfoMsg — enabled via filter rules.
    // Use console.info("[UI] ...") in QML for page navigation logs.
    if (type == QtDebugMsg) return;

    // ── Filter QML engine runtime noise (binding loops, non-existent properties) ──
    // Keep only warning-level noise suppression; info/debug from QML can pass.
    if (type == QtWarningMsg) {
        QString cat = ctx.category ? QString::fromLatin1(ctx.category) : QString();
        if (cat == QStringLiteral("qml") || cat == QStringLiteral("default"))
            return;
        // QML layout anchor warnings (cosmetic, Qt 6 false positives)
        if (msg.contains(QStringLiteral("anchors on an item that is managed by a layout")))
            return;
        // Qt 6 false positive: signal DOES exist in C++
        if (msg.contains(QStringLiteral("but no signal of the target matches the name")))
            return;
    }

    // ── SHADOW_DISABLE_FILE_LOG: skip file I/O entirely (perf testing) ──
    static int disableFileLog = -1;
    if (disableFileLog < 0)
        disableFileLog = qEnvironmentVariableIsSet("SHADOW_DISABLE_FILE_LOG") ? 1 : 0;

    QMutexLocker locker(&g_logMutex);

    // ── Log format: "HH:mm:ss.zzz L [Module] Message" ──
    const QString timestamp =
        QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss.zzz"));

    QString levelStr;
    switch (type) {
    case QtInfoMsg:     levelStr = QStringLiteral("I"); break;
    case QtWarningMsg:  levelStr = QStringLiteral("W"); break;
    case QtCriticalMsg: levelStr = QStringLiteral("E"); break;
    case QtFatalMsg:    levelStr = QStringLiteral("E"); break;
    default:            levelStr = QStringLiteral("?"); break;
    }

    QString module = ctx.category ? QString::fromLatin1(ctx.category) : QStringLiteral("-");
    // Strip "Shadow." prefix for cleaner display: "Shadow.App" → "App"
    if (module.startsWith(QStringLiteral("Shadow.")))
        module = module.mid(7);

    // Strip class name prefix from messages that leak via Qt internals
    QString cleanMsg = msg;
    if (cleanMsg.startsWith(QStringLiteral("ShadowLauncher::")))
        cleanMsg = cleanMsg.mid(16);

    // Strip surrounding quotes (Qt's QDebug adds them when streaming strings)
    if (cleanMsg.size() >= 2 && cleanMsg.startsWith(QChar('"')) && cleanMsg.endsWith(QChar('"')))
        cleanMsg = cleanMsg.mid(1, cleanMsg.size() - 2);

    const QString formatted =
        QStringLiteral("%1 %2 [%3] %4")
            .arg(timestamp, levelStr, module, cleanMsg);

    // ── Write to file (skip if SHADOW_DISABLE_FILE_LOG=1) ──
    if (!disableFileLog) {
        // 连续重复折叠：同一行刷屏时只落第一行，离开重复段时补计数。
        const QString repeatKey = levelStr + QChar(0x1f) + module + QChar(0x1f) + cleanMsg;
        if (repeatKey == g_repeatKey) {
            ++g_repeatCount;
        } else {
            flushRepeatMarker();
            writeRaw(formatted);
            g_repeatKey = repeatKey;
            g_repeatCount = 1;
        }
    }

    // ── Write to debug console (skip if SHADOW_DISABLE_FILE_LOG=1) ──
    if (!disableFileLog) {
        QByteArray utf8 = formatted.toUtf8();
        utf8.append('\n');
#ifdef Q_OS_WIN
        OutputDebugStringA(utf8.constData());
#else
        fwrite(utf8.constData(), 1, utf8.size(), stderr);
#endif
    }

    if (type == QtFatalMsg) {
        flushRepeatMarker();
        if (g_logFile) {
            if (g_logFile->isOpen()) g_logFile->close();
            delete g_logFile;
            g_logFile = nullptr;
        }
        abort();
    }
}

// ============================================================
// Public API
// ============================================================

void initLogger(const QString& exeDir)
{
    installFileLogger(exeDir);
}

void installFileLogger(const QString& exeDir)
{
    QMutexLocker locker(&g_logMutex);

    g_logDir = exeDir;
    g_sessionStart = QDateTime::currentDateTime();
    g_sessionStamp = g_sessionStart.toString(QStringLiteral("yyyy-MM-dd_HH-mm-ss"));

    openSessionLog(exeDir);

    qInstallMessageHandler(shadowMessageHandler);

    // Enable all categories at Info level; disable Debug
    QLoggingCategory::setFilterRules(
        QStringLiteral(
            "Shadow.*.debug=false\n"
            "Shadow.*.info=true\n"
            "qml.info=true\n"
            "qml.debug=false\n"
            "default.debug=false\n"
            "qt.qpa.mime.warning=false\n"
            "qt.network.ssl.warning=false\n"
            "qt.core.qobject.connect.warning=false\n"));

    // 退出时把“重复 N 次”的收尾补上，并留一行会话结束（便于判断是正常退出还是中途被杀）
    if (QCoreApplication::instance()) {
        QObject::connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit,
                         QCoreApplication::instance(), []() {
            QMutexLocker lock(&g_logMutex);
            flushRepeatMarker();
            const qint64 runSecs = g_sessionStart.secsTo(QDateTime::currentDateTime());
            writeRaw(QStringLiteral("——  会话结束（运行 %1 秒）——").arg(runSecs));
        });
    }

    qCInfo(logApp) << QStringLiteral("日志系统已就绪");
}

bool suppressUrlLog()
{
    static int cached = -1;
    if (cached < 0) {
        cached = qEnvironmentVariableIsSet("SHADOW_SUPPRESS_URL_LOG") ? 1 : 0;
        if (cached == 1)
            qCInfo(logApp) << QStringLiteral("[SUPPRESS] URL日志已禁用 (SHADOW_SUPPRESS_URL_LOG=1)");
    }
    return cached == 1;
}

} // namespace ShadowLauncher
