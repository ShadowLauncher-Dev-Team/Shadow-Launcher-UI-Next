// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
// Shadow Launcher — Screenshot Server
//
// Lightweight HTTP server for agent-assisted GUI testing.
// Provides screenshot capture and QML expression evaluation
// so that an AI agent can inspect the rendered UI without
// manual screenshotting or mouse simulation.
//
// 没有任何条件编译：是否创建实例由 main_release.cpp 决定
// （--ui-screenshots 参数或 SHADOW_SS_PORT 环境变量，默认不启动）。
//
// Endpoints:
//   GET  /screenshot          → 200 image/png (window grab)
//   POST /eval   {"qml":"…"}  → 200 application/json {ok, value}
//   POST /navigate {qml|page[+tab]|pageName} → 200 application/json (convenience wrapper)

#ifndef SHADOW_SCREENSHOT_SERVER_H
#define SHADOW_SCREENSHOT_SERVER_H

#include <QObject>
#include <QTcpServer>
#include <QTcpSocket>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QQmlExpression>
#include <QUrl>
#include <QBuffer>

class ScreenshotServer : public QObject
{
    Q_OBJECT

public:
    explicit ScreenshotServer(QQmlApplicationEngine* engine, QObject* parent = nullptr);
    ~ScreenshotServer() override;

    /// Start listening on the given port (binds 127.0.0.1 only).
    /// Returns true on success, false when the port is already taken.
    bool start(quint16 port = 9999);

    /// Stop the server.
    void stop();

    /// Set the window to grab for screenshots.
    void setWindow(QQuickWindow* window);

signals:
    void serverStarted(quint16 port);
    void serverStopped();
    void requestReceived(const QString& method, const QString& path);
    void evalRequested(const QString& expression, bool ok);

private slots:
    void onNewConnection();
    void onReadyRead();

private:
    struct HttpRequest {
        QString method;
        QString path;
        QByteArray body;
    };

    HttpRequest parseRequest(const QByteArray& raw);
    void handleRequest(QTcpSocket* socket, const HttpRequest& req);
    void sendJson(QTcpSocket* socket, int status, const QJsonObject& obj);
    void sendPng(QTcpSocket* socket, const QImage& img);
    void sendError(QTcpSocket* socket, int status, const QString& message);

    QTcpServer* m_server = nullptr;
    QQmlApplicationEngine* m_engine = nullptr;
    QQuickWindow* m_window = nullptr;
};

#endif // SHADOW_SCREENSHOT_SERVER_H
