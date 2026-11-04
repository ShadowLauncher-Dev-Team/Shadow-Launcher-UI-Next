// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2025-2026 影 / Shadow / xiaole1173
#include "step_node.h"

namespace ShadowLauncher {

StepNode::StepNode(const QString& key, const QString& displayName,
                   qreal weight, QObject* parent)
    : QObject(parent)
    , m_key(key)
    , m_name(displayName)
    , m_weight(qMax(0.01, weight))
{
}

void StepNode::setStatus(const QString& s) {
    if (s == QStringLiteral("active")) setActive();
    else if (s == QStringLiteral("completed")) setCompleted();
    else if (s == QStringLiteral("failed")) setFailed();
    else if (s == QStringLiteral("skipped")) setSkipped();
    else setStatus(StepStatus::Pending);
}

static bool isTerminalStatus(StepStatus s) {
    return s == StepStatus::Completed || s == StepStatus::Failed || s == StepStatus::Skipped;
}

void StepNode::setStatus(StepStatus s) {
    // 契约：终态不可逆。completed → active、completed → failed 之类的迁移一律丢弃，
    // 否则界面会出现"已经绿的步骤又冒三点"（旧 UI 实测过的观感）。
    if (isTerminalStatus(m_status) && m_status != s) return;

    const bool becameCompleted = (s == StepStatus::Completed);
    if (m_status == s) {
        if (becameCompleted && m_percentage < 100) {
            m_percentage = 100;
            emit progressChanged();
        }
        return;
    }
    m_status = s;
    emit statusChanged();
    if (becameCompleted && m_percentage < 100) {
        // 完成即 100%：避免"状态已完成、进度停在 87%"的错位
        m_percentage = 100;
        emit progressChanged();
    }
}

void StepNode::forceStatus(StepStatus s) {
    const bool pctChanged = (s == StepStatus::Completed && m_percentage < 100);
    if (pctChanged) m_percentage = 100;
    if (m_status == s) {
        if (pctChanged) emit progressChanged();
        return;
    }
    m_status = s;
    emit statusChanged();
    if (pctChanged) emit progressChanged();
}

void StepNode::setFailed(const QString& error) {
    m_errorMsg = error;
    setStatus(StepStatus::Failed);
}

void StepNode::setPercentage(int pct) {
    pct = qBound(0, pct, 100);
    // 已完成的步骤不允许把进度拉回（契约 §1 进度单调）
    if (m_status == StepStatus::Completed) pct = 100;
    if (m_percentage == pct) return;
    m_percentage = pct;
    emit progressChanged();
}

void StepNode::setByteProgress(qint64 recv, qint64 total) {
    if (m_bytesRecv == recv && m_bytesTotal == total) return;
    m_bytesRecv = recv;
    m_bytesTotal = total;
    if (total > 0) {
        // 2026-08-14：钳制——驿道下载 recv 可超过 total（分片/206/合并场景），
        // 直接 recv*100/total 会算出超 100% 的进度（实测主文件 120%）。
        int pct = static_cast<int>(qMin<qint64>(recv * 100 / total, 100));
        // 完成的步骤不接受字节进度回写（否则 completed 后又被拉到 87%）
        if (m_status == StepStatus::Completed) pct = 100;
        if (pct != m_percentage) {
            m_percentage = pct;
        }
    }
    emit progressChanged();
}

void StepNode::setHidden(bool h) {
    if (m_hidden == h) return;
    m_hidden = h;
    emit hiddenChanged();
}

void StepNode::setDetail(const QString& d) {
    if (m_detail == d) return;
    m_detail = d;
    emit detailChanged();
}

} // namespace ShadowLauncher
