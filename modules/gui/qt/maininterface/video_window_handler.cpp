/*****************************************************************************
 * Copyright (C) 2020 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/
#include "video_window_handler.hpp"
#include "mainctx.hpp"

#include <QApplication>
#include <QScreen>
#include <QQuickItem>
#include <QQuickWindow>

#include <vlc_window.h>
#include "compositor.hpp"

VideoWindowHandler::VideoWindowHandler(qt_intf_t* intf, QObject *parent)
    : QObject(parent)
    , m_intf(intf)
{
    /* Does the interface resize to video size or the opposite */
    m_autoresize = var_InheritBool( m_intf, "qt-video-autoresize" );

    assert(qGuiApp);
    m_hasWayland = qGuiApp->platformName().startsWith(QLatin1String("wayland"));

    connect( this, &VideoWindowHandler::askVideoToResize,
             this, &VideoWindowHandler::setVideoSize, Qt::QueuedConnection );
    connect( this, &VideoWindowHandler::askVideoSetFullScreen,
             this, &VideoWindowHandler::setVideoFullScreen, Qt::QueuedConnection );
    connect( this, &VideoWindowHandler::askVideoOnTop,
             this, &VideoWindowHandler::setVideoOnTop, Qt::QueuedConnection );
}

void VideoWindowHandler::setWindow(QWindow* window)
{
    if (m_window == window)
        return;
    if (m_window)
    {
        WindowStateHolder::holdOnTop(m_window, WindowStateHolder::VIDEO, false);
        WindowStateHolder::holdFullscreen(m_window, WindowStateHolder::VIDEO, false);
    }

    m_window = window;
}

void VideoWindowHandler::disable()
{
    emit askVideoSetFullScreen( false );
    emit askVideoOnTop( false );
}

void VideoWindowHandler::requestResizeVideo( unsigned i_width, unsigned i_height )
{
    if (!m_window)
        return;
    emit askVideoToResize( i_width, i_height, m_window->windowStates() );
}

void VideoWindowHandler::requestVideoWindowed( )
{
   emit askVideoSetFullScreen( false );
}

void VideoWindowHandler::requestVideoFullScreen(const char * )
{
    emit askVideoSetFullScreen( true );
}

void VideoWindowHandler::requestVideoState(  unsigned i_arg )
{
    bool on_top = (i_arg & VLC_WINDOW_STATE_ABOVE) != 0;
    emit askVideoOnTop( on_top );
}

void VideoWindowHandler::setVideoSize(unsigned int w, unsigned int h, Qt::WindowStates currentStates)
{
    if (!m_window)
        return;
    Qt::WindowStates states = m_window->windowStates();

    // This slot is queued, so by the time it is called
    // the window states reflect the final states.
    // `qt-video-autoresize` should not apply during state
    // transition, that was also the behavior in VLC 3.
    // Otherwise, when getting disengaged from fullscreen
    // the interface/video would forget its old (overridden)
    // size.

    // Do not resize when transitioning between states:
    if (currentStates != states)
        return;

    if ((states & (Qt::WindowFullScreen | Qt::WindowMaximized)) == 0)
    {
        /* Resize video widget to video size, or keep it at the same
         * size. Call setSize() either way so that vlc_window_ReportSize
         * will always get called.
         * If the video size is too large for the screen, resize it
         * to the screen size.
         */
        if (m_autoresize)
        {
            QRect screen = m_window->screen()->availableGeometry();
            qreal factor = m_window->devicePixelRatio();

            // Convert the video size to logical pixels first
            w = qRound( (float)w / factor );
            h = qRound( (float)h / factor );
            msg_Dbg( m_intf, "Logical video size: %ux%u", w, h );

            if (w == 0 || h == 0)
                return;

            const double videoAspect = static_cast<double>(w) / static_cast<double>(h);

            // Pinned controls occupy space outside the video surface.
            QSize chrome(0, 0);
            if (m_intf->p_compositor)
            {
                if (auto quickWindow = m_intf->p_compositor->quickWindow())
                {
                    if (auto loader = quickWindow->contentItem()->findChild<QQuickItem*>(QStringLiteral("playerSpecializationLoader")))
                    {
                        chrome = QSize(std::max(0, m_window->width() - qRound(loader->width())),
                                       std::max(0, m_window->height() - qRound(loader->height())));
                    }
                }
            }
            const double maxW = std::max(1.0, screen.width() * 0.75 - chrome.width());
            const double maxH = std::max(1.0, screen.height() * 0.75 - chrome.height());

            double targetW = w;
            double targetH = h;

            if (targetW > maxW || targetH > maxH)
            {
                const double scale = std::min(maxW / targetW, maxH / targetH);
                targetW = std::max(1.0, targetW * scale);
                targetH = std::max(1.0, targetH * scale);
            }

            // Ensure window meets minimum constraints without distorting the video aspect ratio
            const double minW = std::max(1.0, static_cast<double>(m_window->minimumWidth() - chrome.width()));
            const double minH = std::max(1.0, static_cast<double>(m_window->minimumHeight() - chrome.height()));

            if (targetW < minW)
            {
                targetW = minW;
                targetH = targetW / videoAspect;
            }
            if (targetH < minH)
            {
                targetH = minH;
                targetW = targetH * videoAspect;
            }

            // Re-check max bounds in case minimums forced an upscale
            if (targetW > maxW || targetH > maxH)
            {
                const double scale = std::min(maxW / targetW, maxH / targetH);
                targetW = std::max(1.0, targetW * scale);
                targetH = std::max(1.0, targetH * scale);
            }

            const int finalW = std::clamp(qRound(targetW) + chrome.width(),
                                          m_window->minimumWidth(), m_window->maximumWidth());
            const int finalH = std::clamp(qRound(targetH) + chrome.height(),
                                          m_window->minimumHeight(), m_window->maximumHeight());

            msg_Dbg( m_intf, "Resizing window to video aspect ratio: %ix%i (aspect %.3f)", finalW, finalH, videoAspect );

            // Center or clamp position so resized window stays within available screen geometry
            QRect winGeom = m_window->geometry();
            int newX = winGeom.x();
            int newY = winGeom.y();
            winGeom.setWidth(finalW);
            winGeom.setHeight(finalH);
            if (!screen.contains(winGeom))
            {
                newX = std::clamp(winGeom.x(), screen.left(), std::max(screen.left(), screen.right() - finalW));
                newY = std::clamp(winGeom.y(), screen.top(), std::max(screen.top(), screen.bottom() - finalH));
            }
            m_window->setGeometry(newX, newY, finalW, finalH);
        }
    }
}

void VideoWindowHandler::setVideoFullScreen( bool fs )
{
    if (!m_window)
        return;
    m_videoFullScreen = fs;
    if( fs )
    {
        int numscreen = var_InheritInteger( m_intf, "qt-fullscreen-screennumber" );

        auto screenList = QApplication::screens();
        if ( numscreen >= 0 && numscreen < screenList.count() )
        {
            QRect screenres = screenList[numscreen]->geometry();
            m_lastWinScreen = m_window->screen();
            if( !m_hasWayland )
                m_window->setScreen(screenList[numscreen]);

            /* To be sure window is on proper-screen in xinerama */
            if( !screenres.contains( m_window->position() ) )
            {
                m_window->setPosition(screenres.x(), screenres.y() );
            }
        }
        WindowStateHolder::holdFullscreen(m_window,  WindowStateHolder::VIDEO, true);
    }
    else
    {
        WindowStateHolder::holdFullscreen(m_window,  WindowStateHolder::VIDEO, false);

        if( m_lastWinScreen != NULL && !m_hasWayland )
            m_window->setScreen(m_lastWinScreen);
    }
}


/* Slot to change the video always-on-top flag.
 * Emit askVideoOnTop() to invoke this from other thread. */
void VideoWindowHandler::setVideoOnTop( bool on_top )
{
    if (!m_window)
        return;
    WindowStateHolder::holdOnTop(m_window, WindowStateHolder::VIDEO, on_top);
}
